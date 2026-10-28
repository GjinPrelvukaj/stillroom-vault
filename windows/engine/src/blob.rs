//! Reading one sealing of an item from `Files/`: the read side of `VaultStore.open` and `Storage/Chunked.swift`.
//!
//! A blob is in one of two forms (docs/FORMAT.md, "Each file's contents"):
//! - one piece: the Padmé-padded bytes sealed once, bound to `"Vault item 3" | sealedAs`;
//! - chunks ("VLT2"), for big files and all audio and video, each bound to `sealedAs | index (u64) | last`.
//!
//! Which form it is comes from the list's `chunked`, never from the blob.

use std::fs::File;
use std::io::{Read, Seek, SeekFrom, Write};
use std::ops::Range;
use std::path::Path;
use std::sync::Mutex;

use uuid::Uuid;
use zeroize::Zeroizing;

use crate::crypto::{bound, padded_length, unseal, Key};
use crate::VaultError;

pub const CHUNK_MAGIC: &[u8; 4] = b"VLT2";
pub const HEADER_SIZE: u64 = 8;
/// What sealing adds to each chunk: the nonce and the tag.
pub const OVERHEAD: u64 = 28;
/// The chunk size the Mac app writes.
pub const CHUNK_SIZE: u64 = 1 << 20;

/// Why reading a sealing out failed: the sealing itself, or where it was being written.
#[derive(Debug)]
pub enum ReadError {
    Damaged(VaultError),
    Writing(std::io::Error),
}

impl From<VaultError> for ReadError {
    fn from(error: VaultError) -> Self {
        ReadError::Damaged(error)
    }
}

/// The real bytes of one sealing, written to `out`. Every chunk is opened, padding too, so a cut-short blob fails
/// rather than coming out short.
pub fn read_into(path: &Path, sealed_as: &Uuid, key: &Key, size: u64, chunked: bool, out: &mut impl Write) -> Result<(), ReadError> {
    if chunked {
        let reader = ChunkedReader::open(path, key, sealed_as, size)?;
        for index in 0..reader.count() {
            let chunk = reader.chunk(index)?;
            let start = index * reader.chunk_size();
            let real = size.saturating_sub(start).min(chunk.len() as u64) as usize;
            out.write_all(&chunk[..real]).map_err(ReadError::Writing)?;
        }
        return Ok(());
    }
    // The blob must be a plain file exactly as long as this size seals to, checked before any of it is read, so a
    // doctored one can't make this read something huge (or a device) into memory.
    let expected = padded_length(size).and_then(|n| n.checked_add(OVERHEAD)).ok_or(VaultError::Damaged)?;
    let mut file = File::open(path).map_err(|_| VaultError::Damaged)?;
    let metadata = file.metadata().map_err(|_| VaultError::Damaged)?;
    if !metadata.is_file() || metadata.len() != expected {
        return Err(VaultError::Damaged.into());
    }
    let mut sealed = Vec::new();
    sealed.try_reserve_exact(usize::try_from(expected).map_err(|_| VaultError::Damaged)?).map_err(|_| VaultError::Damaged)?;
    file.read_to_end(&mut sealed).map_err(|_| VaultError::Damaged)?;
    if sealed.len() as u64 != expected {
        return Err(VaultError::Damaged.into());
    }
    let plain = unseal(&sealed, key, Some(&bound::item(sealed_as.as_bytes())))?;
    let size = usize::try_from(size).map_err(|_| VaultError::Damaged)?;
    if plain.len() < size {
        return Err(VaultError::Damaged.into());
    }
    out.write_all(&plain[..size]).map_err(ReadError::Writing)
}

/// The whole of one sealing in memory, for small files and previews.
pub fn read(path: &Path, sealed_as: &Uuid, key: &Key, size: u64, chunked: bool) -> Result<Zeroizing<Vec<u8>>, VaultError> {
    // Sized up front, so the buffer never grows and leaves an unwiped copy behind.
    let mut data = Zeroizing::new(Vec::new());
    data.try_reserve_exact(usize::try_from(size).map_err(|_| VaultError::Damaged)?).map_err(|_| VaultError::Damaged)?;
    read_into(path, sealed_as, key, size, chunked, &mut *data).map_err(|error| match error {
        ReadError::Damaged(error) => error,
        // Writing into memory that's already reserved can't fail.
        ReadError::Writing(_) => VaultError::Damaged,
    })?;
    Ok(data)
}

/// Seals `size` bytes from `source` chunk by chunk into `destination` (never the whole file in memory), padding the
/// plaintext with zeros to `padded_length(size)`. Written beside the destination and renamed into place, so a crash
/// leaves the old blob or none. A source that gives fewer bytes than `size` (a file that shrank while being read) fails
/// rather than going in with zeros where its end was.
pub fn seal_chunked(mut source: impl Read, size: u64, destination: &Path, key: &Key, sealed_as: &Uuid) -> Result<(), crate::Error> {
    let folder = destination.parent().ok_or(VaultError::Damaged)?;
    std::fs::create_dir_all(folder)?;
    let temp = folder.join(format!(".{}.partial", Uuid::new_v4().hyphenated()));
    let written = (|| -> Result<(), crate::Error> {
        let mut out = std::io::BufWriter::new(File::create(&temp)?);
        out.write_all(CHUNK_MAGIC)?;
        out.write_all(&(CHUNK_SIZE as u32).to_be_bytes())?;
        let padded = padded_length(size).ok_or(VaultError::Damaged)?;
        let count = chunk_count(size, CHUNK_SIZE).ok_or(VaultError::Damaged)?;
        let mut chunk = Zeroizing::new(Vec::with_capacity(CHUNK_SIZE as usize));
        for index in 0..count {
            let start = index * CHUNK_SIZE;
            let length = CHUNK_SIZE.min(padded - start);
            let real = size.saturating_sub(start).min(length);
            chunk.clear();
            chunk.resize(real as usize, 0);
            source.read_exact(&mut chunk).map_err(|_| VaultError::Damaged)?;
            chunk.resize(length as usize, 0);
            out.write_all(&crate::crypto::seal(&chunk, key, Some(&chunk_binding(sealed_as, index, index == count - 1)))?)?;
        }
        let file = out.into_inner().map_err(|e| e.into_error())?;
        file.sync_all()?;
        drop(file);
        std::fs::rename(&temp, destination)?;
        Ok(())
    })();
    if written.is_err() {
        let _ = std::fs::remove_file(&temp);
    }
    written
}

/// What each chunk's seal is bound to: the sealing, the chunk's place, and whether it's the last.
pub fn chunk_binding(sealed_as: &Uuid, index: u64, last: bool) -> Vec<u8> {
    let mut data = sealed_as.as_bytes().to_vec();
    data.extend_from_slice(&index.to_be_bytes());
    data.push(u8::from(last));
    data
}

/// How many chunks a file of this real size seals into: at least one, so even an empty file has a last chunk to show
/// it wasn't cut short.
/// None for a chunk size of 0 or a size too large to pad.
pub fn chunk_count(plain_size: u64, chunk_size: u64) -> Option<u64> {
    if chunk_size == 0 {
        return None;
    }
    Some(padded_length(plain_size)?.div_ceil(chunk_size).max(1))
}

/// Reads any range of a chunked blob, opening only the chunks the range touches. Safe to share between threads.
pub struct ChunkedReader {
    file: Mutex<File>,
    key: Key,
    sealed_as: Uuid,
    chunk_size: u64,
    count: u64,
    plain_size: u64,
    padded_size: u64,
    /// One chunk cached, enough for a player reading forward.
    cached: Mutex<Option<(u64, Zeroizing<Vec<u8>>)>>,
}

impl ChunkedReader {
    pub fn open(path: &Path, key: &Key, sealed_as: &Uuid, plain_size: u64) -> Result<ChunkedReader, VaultError> {
        let mut file = File::open(path).map_err(|_| VaultError::Damaged)?;
        let mut header = [0u8; HEADER_SIZE as usize];
        file.read_exact(&mut header).map_err(|_| VaultError::Damaged)?;
        if &header[..4] != CHUNK_MAGIC {
            return Err(VaultError::Damaged);
        }
        let chunk_size = u64::from(u32::from_be_bytes(header[4..].try_into().unwrap()));
        // A sane chunk size only: a changed header can't make one chunk the size of the disk. A size past 1 PiB can't
        // be real and would overflow the length sums below.
        if !(1..=64 << 20).contains(&chunk_size) || plain_size > 1 << 50 {
            return Err(VaultError::Damaged);
        }
        let padded_size = padded_length(plain_size).ok_or(VaultError::Damaged)?;
        let count = chunk_count(plain_size, chunk_size).ok_or(VaultError::Damaged)?;
        // The real size comes from the sealed list, so the blob must be exactly as long as that size seals to: a
        // dropped or added chunk fails here, before any range is read.
        let expected = count
            .checked_mul(OVERHEAD)
            .and_then(|n| n.checked_add(HEADER_SIZE))
            .and_then(|n| n.checked_add(padded_size))
            .ok_or(VaultError::Damaged)?;
        let metadata = file.metadata().map_err(|_| VaultError::Damaged)?;
        if !metadata.is_file() || metadata.len() != expected {
            return Err(VaultError::Damaged);
        }
        Ok(ChunkedReader {
            file: Mutex::new(file),
            key: Key::from_slice(key.as_bytes())?,
            sealed_as: *sealed_as,
            chunk_size,
            count,
            plain_size,
            padded_size,
            cached: Mutex::new(None),
        })
    }

    pub fn chunk_size(&self) -> u64 {
        self.chunk_size
    }

    pub fn count(&self) -> u64 {
        self.count
    }

    pub fn plain_size(&self) -> u64 {
        self.plain_size
    }

    /// One chunk opened, padding included.
    pub fn chunk(&self, index: u64) -> Result<Zeroizing<Vec<u8>>, VaultError> {
        let mut cached = self.cached.lock().unwrap();
        if let Some((at, data)) = cached.as_ref() {
            if *at == index {
                return Ok(data.clone());
            }
        }
        if index >= self.count {
            return Err(VaultError::Damaged);
        }
        let length = self.chunk_size.min(self.padded_size - index * self.chunk_size) + OVERHEAD;
        let mut sealed = vec![0u8; length as usize];
        {
            let mut file = self.file.lock().unwrap();
            file.seek(SeekFrom::Start(HEADER_SIZE + index * (self.chunk_size + OVERHEAD)))
                .and_then(|_| file.read_exact(&mut sealed))
                .map_err(|_| VaultError::Damaged)?;
        }
        let binding = chunk_binding(&self.sealed_as, index, index == self.count - 1);
        let data = unseal(&sealed, &self.key, Some(&binding))?;
        *cached = Some((index, data.clone()));
        Ok(data)
    }

    /// The bytes in `range`, clamped to the real size (a player may ask past the end).
    pub fn read(&self, range: Range<u64>) -> Result<Zeroizing<Vec<u8>>, VaultError> {
        let range = range.start.min(self.plain_size)..range.end.min(self.plain_size);
        let mut data = Zeroizing::new(Vec::with_capacity((range.end.saturating_sub(range.start)) as usize));
        if range.is_empty() {
            return Ok(data);
        }
        for index in range.start / self.chunk_size..=(range.end - 1) / self.chunk_size {
            let chunk = self.chunk(index)?;
            let start = index * self.chunk_size;
            let from = range.start.max(start) - start;
            let to = range.end.min(start + chunk.len() as u64) - start;
            data.extend_from_slice(&chunk[from as usize..to as usize]);
        }
        Ok(data)
    }
}
