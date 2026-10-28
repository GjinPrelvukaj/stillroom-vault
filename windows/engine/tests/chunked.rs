//! The chunked format ("VLT2") sealed and read back, as the Mac's ChunkedTests check it: every size round-trips, any
//! range reads back, and a changed, swapped, dropped or foreign chunk fails.

use std::fs;
use std::path::{Path, PathBuf};

use stillroom_core::blob::{self, chunk_count, seal_chunked, ChunkedReader, CHUNK_SIZE};
use stillroom_core::crypto::{padded_size, Key};
use stillroom_core::VaultError;
use uuid::Uuid;

const CS: usize = CHUNK_SIZE as usize;

fn random(count: usize) -> Vec<u8> {
    let mut data = vec![0u8; count];
    stillroom_core::crypto::fill_random(&mut data);
    data
}

struct Bench {
    dir: tempfile::TempDir,
    key: Key,
    id: Uuid,
}

impl Bench {
    fn new() -> Bench {
        Bench { dir: tempfile::tempdir().unwrap(), key: Key::random(), id: Uuid::new_v4() }
    }

    fn path(&self, name: &str) -> PathBuf {
        self.dir.path().join(name)
    }

    /// A blob of several chunks, for the tamper tests.
    fn sealed_sample(&self) -> (PathBuf, Vec<u8>) {
        let plain = random(3 * CS + 5);
        let blob = self.path("sample.stillroom");
        seal_chunked(&plain[..], plain.len() as u64, &blob, &self.key, &self.id).unwrap();
        (blob, plain)
    }

    fn read(&self, blob: &Path, size: usize) -> Result<Vec<u8>, VaultError> {
        blob::read(blob, &self.id, &self.key, size as u64, true).map(|d| d.to_vec())
    }
}

#[test]
fn every_size_round_trips_from_a_file_and_from_memory() {
    for size in [0, 1, CS - 1, CS, CS + 1, 3 * CS + 5] {
        let bench = Bench::new();
        let plain = random(size);
        fs::write(bench.path("in"), &plain).unwrap();
        let blob = bench.path("out.stillroom");
        seal_chunked(fs::File::open(bench.path("in")).unwrap(), size as u64, &blob, &bench.key, &bench.id).unwrap();
        assert_eq!(bench.read(&blob, size).unwrap(), plain, "{size}");
        // Padded like a one-piece item, plus a header and each chunk's nonce and tag.
        let chunks = chunk_count(size as u64, CHUNK_SIZE).unwrap() as usize;
        assert_eq!(fs::metadata(&blob).unwrap().len() as usize, 8 + chunks * 28 + padded_size(size).unwrap());
        // Nothing left beside it but what was asked for.
        let mut names: Vec<String> = fs::read_dir(bench.dir.path()).unwrap().map(|e| e.unwrap().file_name().to_string_lossy().into()).collect();
        names.sort();
        assert_eq!(names, ["in", "out.stillroom"]);

        seal_chunked(&plain[..], size as u64, &blob, &bench.key, &bench.id).unwrap();
        assert_eq!(bench.read(&blob, size).unwrap(), plain, "{size} from memory");
    }
}

#[test]
fn random_ranges_match_the_plaintext() {
    let bench = Bench::new();
    let (blob, plain) = bench.sealed_sample();
    let reader = ChunkedReader::open(&blob, &bench.key, &bench.id, plain.len() as u64).unwrap();
    let n = plain.len() as u64;
    let mut ranges = vec![0..0, 0..1, 0..n, CS as u64 - 1..CS as u64 + 1, n - 1..n];
    let mut bytes = [0u8; 16];
    for _ in 0..200 {
        stillroom_core::crypto::fill_random(&mut bytes);
        let a = u64::from_le_bytes(bytes[..8].try_into().unwrap()) % (n + 1);
        let b = u64::from_le_bytes(bytes[8..].try_into().unwrap()) % (n + 1);
        ranges.push(a.min(b)..a.max(b));
    }
    for range in ranges {
        assert!(*reader.read(range.clone()).unwrap() == plain[range.start as usize..range.end as usize], "{range:?}");
    }
    // A player may ask past the end: it gets what there is.
    assert_eq!(*reader.read(n - 3..n + 100).unwrap(), plain[plain.len() - 3..]);
}

#[test]
fn a_flipped_byte_fails_only_its_chunk() {
    let bench = Bench::new();
    let (blob, plain) = bench.sealed_sample();
    let mut bytes = fs::read(&blob).unwrap();
    bytes[8 + CS + 28 + 100] ^= 1;
    fs::write(&blob, bytes).unwrap();
    assert_eq!(bench.read(&blob, plain.len()).err(), Some(VaultError::Damaged));
    let reader = ChunkedReader::open(&blob, &bench.key, &bench.id, plain.len() as u64).unwrap();
    assert_eq!(*reader.read(0..10).unwrap(), plain[..10]);
    assert_eq!(reader.read(CS as u64..CS as u64 + 10).err(), Some(VaultError::Damaged));
}

#[test]
fn swapped_chunks_fail() {
    let bench = Bench::new();
    let (blob, plain) = bench.sealed_sample();
    let bytes = fs::read(&blob).unwrap();
    let n = CS + 28;
    let swapped = [&bytes[..8], &bytes[8 + n..8 + 2 * n], &bytes[8..8 + n], &bytes[8 + 2 * n..]].concat();
    fs::write(&blob, swapped).unwrap();
    assert_eq!(bench.read(&blob, plain.len()).err(), Some(VaultError::Damaged));
    let reader = ChunkedReader::open(&blob, &bench.key, &bench.id, plain.len() as u64).unwrap();
    assert_eq!(reader.read(0..1).err(), Some(VaultError::Damaged));
}

#[test]
fn a_dropped_last_chunk_fails() {
    let bench = Bench::new();
    let (blob, plain) = bench.sealed_sample();
    let bytes = fs::read(&blob).unwrap();
    fs::write(&blob, &bytes[..8 + 3 * (CS + 28)]).unwrap();
    assert!(ChunkedReader::open(&blob, &bench.key, &bench.id, plain.len() as u64).is_err());
    // Even told the shorter size, the chunk that's now last wasn't sealed as the last.
    let shorter = ChunkedReader::open(&blob, &bench.key, &bench.id, 3 * CS as u64).unwrap();
    assert_eq!(shorter.read(3 * CS as u64 - 1..3 * CS as u64).err(), Some(VaultError::Damaged));
}

#[test]
fn another_files_blob_fails() {
    let bench = Bench::new();
    let (blob, plain) = bench.sealed_sample();
    assert!(blob::read(&blob, &Uuid::new_v4(), &bench.key, plain.len() as u64, true).is_err());
    assert!(blob::read(&blob, &bench.id, &Key::random(), plain.len() as u64, true).is_err());
}

/// Found by fuzzing on the Mac: an impossible size (the list says the largest number there is) is refused, not an
/// arithmetic-overflow crash.
#[test]
fn an_impossible_size_is_refused() {
    let bench = Bench::new();
    let blob = bench.path("huge.stillroom");
    seal_chunked(&b"small"[..], 5, &blob, &bench.key, &bench.id).unwrap();
    for size in [u64::MAX, u64::MAX / 2, 1 << 62] {
        assert!(ChunkedReader::open(&blob, &bench.key, &bench.id, size).is_err());
        assert!(blob::read(&blob, &bench.id, &bench.key, size, false).is_err());
    }
}

/// A file that shrank while being read fails rather than going in with zeros where its end was, and leaves nothing.
#[test]
fn a_source_that_shrinks_fails_and_leaves_nothing() {
    let bench = Bench::new();
    let blob = bench.path("short.stillroom");
    let told = 2 * CS as u64;
    assert!(seal_chunked(&random(CS + 10)[..], told, &blob, &bench.key, &bench.id).is_err());
    assert_eq!(fs::read_dir(bench.dir.path()).unwrap().count(), 0);
}
