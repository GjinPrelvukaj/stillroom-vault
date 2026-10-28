//! Where keys live: pages of memory Windows may not write to the page file (`VirtualLock`), carved into 32-byte slots,
//! one per key, each wiped when its key is dropped (windows/PORT.md, "Rust core for everything that touches keys").
//!
//! A key never sits in ordinary heap memory: `VirtualLock` works on whole pages, and locking pages shared with the rest
//! of the heap would lock data that isn't secret and unlock keys when that data is freed. So keys get pages of their
//! own, allocated with `VirtualAlloc` 64 KiB at a time (2048 slots), and a slot freed is wiped and reused.
//!
//! What locking doesn't do: hibernation writes every page of memory to hiberfil.sys, locked or not, and a debugger or
//! malware running as you reads memory directly. BitLocker (or Device Encryption) is what protects the first; nothing
//! in an app protects against the second.
//!
//! If Windows won't lock more pages (each process may lock only as much as its minimum working set), the arena raises
//! that minimum and tries again. If it still can't, keys go in unlocked pages rather than failing, and
//! `status().all_locked` says so, for the app to warn.

use std::ptr::NonNull;
use std::sync::Mutex;

use zeroize::Zeroize;

pub const KEY_LENGTH: usize = 32;
/// What `VirtualAlloc` hands out at once anyway (the allocation granularity).
const CHUNK: usize = 64 * 1024;
const SLOTS_PER_CHUNK: usize = CHUNK / KEY_LENGTH;

/// One key's 32 bytes, in a locked page. Wiped and given back when dropped.
pub struct Slot(NonNull<[u8; KEY_LENGTH]>);

// A slot is owned by exactly one key; the arena hands each one out once.
unsafe impl Send for Slot {}
unsafe impl Sync for Slot {}

impl Slot {
    pub fn new() -> Slot {
        let mut arena = ARENA.lock().unwrap_or_else(|e| e.into_inner());
        Slot(arena.take())
    }

    pub fn bytes(&self) -> &[u8; KEY_LENGTH] {
        // SAFETY: the slot points into a committed chunk that's never freed, and only this `Slot` uses it.
        unsafe { self.0.as_ref() }
    }

    pub fn bytes_mut(&mut self) -> &mut [u8; KEY_LENGTH] {
        // SAFETY: as above, and `&mut self` means no other reference to these bytes exists.
        unsafe { self.0.as_mut() }
    }
}

impl Default for Slot {
    fn default() -> Slot {
        Slot::new()
    }
}

impl Drop for Slot {
    fn drop(&mut self) {
        self.bytes_mut().zeroize();
        let mut arena = ARENA.lock().unwrap_or_else(|e| e.into_inner());
        arena.free.push(SlotPointer(self.0));
    }
}

/// How the arena stands: for tests, and for the app to tell someone their keys can't be kept out of the page file.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Status {
    pub chunks: usize,
    pub keys: usize,
    /// Every chunk of key memory is locked (out of the page file). False when Windows refused, or off Windows.
    pub all_locked: bool,
}

pub fn status() -> Status {
    let arena = ARENA.lock().unwrap_or_else(|e| e.into_inner());
    Status {
        chunks: arena.chunks.len(),
        keys: arena.chunks.len() * SLOTS_PER_CHUNK - arena.free.len(),
        all_locked: !arena.chunks.is_empty() && arena.chunks.iter().all(|c| c.locked),
    }
}

/// Keeps this program out of Windows Error Reporting, so a crash never writes its memory (keys included) to a report or
/// a local dump. Per user, kept by Windows across restarts; the app calls it once as it starts. `remove` takes it out
/// again (for tests).
pub fn exclude_from_crash_reports(remove: bool) -> Result<(), i32> {
    platform::exclude_from_crash_reports(remove)
}

struct SlotPointer(NonNull<[u8; KEY_LENGTH]>);
unsafe impl Send for SlotPointer {}

struct Chunk {
    #[allow(dead_code)]
    start: SlotPointer,
    locked: bool,
}

struct Arena {
    chunks: Vec<Chunk>,
    free: Vec<SlotPointer>,
}

static ARENA: Mutex<Arena> = Mutex::new(Arena { chunks: Vec::new(), free: Vec::new() });

impl Arena {
    fn take(&mut self) -> NonNull<[u8; KEY_LENGTH]> {
        if self.free.is_empty() {
            self.grow();
        }
        self.free.pop().expect("a chunk was just added").0
    }

    /// One more chunk of key slots, locked if Windows allows it.
    fn grow(&mut self) {
        let (start, locked) = platform::allocate_locked(CHUNK);
        let start = NonNull::new(start.cast::<[u8; KEY_LENGTH]>()).expect("out of memory for keys");
        // Handed out from the end of the list, so lowest first; it doesn't matter which.
        for i in (0..SLOTS_PER_CHUNK).rev() {
            // SAFETY: i < SLOTS_PER_CHUNK keeps every slot inside the chunk just committed.
            self.free.push(SlotPointer(unsafe { NonNull::new_unchecked(start.as_ptr().add(i)) }));
        }
        self.chunks.push(Chunk { start: SlotPointer(start), locked });
    }
}

#[cfg(windows)]
mod platform {
    use std::ffi::c_void;

    use windows_sys::Win32::System::Memory::{
        GetProcessWorkingSetSizeEx, SetProcessWorkingSetSizeEx, VirtualAlloc, VirtualLock, MEM_COMMIT, MEM_RESERVE,
        PAGE_READWRITE, QUOTA_LIMITS_HARDWS_MIN_DISABLE, QUOTA_LIMITS_HARDWS_MAX_DISABLE,
    };
    use windows_sys::Win32::System::Threading::GetCurrentProcess;

    /// `size` bytes of zeroed, committed memory of its own, and whether it could be locked out of the page file.
    pub fn allocate_locked(size: usize) -> (*mut c_void, bool) {
        // SAFETY: plain Win32 calls on memory this function owns; failures are checked.
        unsafe {
            let start = VirtualAlloc(std::ptr::null(), size, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
            if start.is_null() {
                return (start, false);
            }
            if VirtualLock(start, size) != 0 {
                return (start, true);
            }
            // A process may lock only up to its minimum working set: raise it by this chunk and try once more.
            let (mut min, mut max, mut flags) = (0usize, 0usize, 0u32);
            let process = GetCurrentProcess();
            if GetProcessWorkingSetSizeEx(process, &mut min, &mut max, &mut flags) != 0 {
                let grown = SetProcessWorkingSetSizeEx(
                    process,
                    min + size,
                    max.max(min + size) + size,
                    QUOTA_LIMITS_HARDWS_MIN_DISABLE | QUOTA_LIMITS_HARDWS_MAX_DISABLE,
                );
                if grown != 0 && VirtualLock(start, size) != 0 {
                    return (start, true);
                }
            }
            (start, false)
        }
    }

    /// This program's own path, as Windows Error Reporting names it.
    pub fn exclude_from_crash_reports(remove: bool) -> Result<(), i32> {
        use windows_sys::Win32::System::ErrorReporting::{WerAddExcludedApplication, WerRemoveExcludedApplication};
        use windows_sys::Win32::System::LibraryLoader::GetModuleFileNameW;
        let mut path = vec![0u16; 32_768];
        // SAFETY: the buffer is as long as the length given; the path is NUL-terminated by Windows (and by the vec's
        // zeros past it) before WER reads it.
        unsafe {
            let length = GetModuleFileNameW(std::ptr::null_mut(), path.as_mut_ptr(), path.len() as u32) as usize;
            if length == 0 || length >= path.len() {
                return Err(-1);
            }
            let result = if remove {
                WerRemoveExcludedApplication(path.as_ptr(), 0)
            } else {
                WerAddExcludedApplication(path.as_ptr(), 0)
            };
            if result < 0 { Err(result) } else { Ok(()) }
        }
    }
}

#[cfg(not(windows))]
mod platform {
    /// Off Windows (tests on a Mac, say): ordinary memory, never freed, and not locked.
    pub fn allocate_locked(size: usize) -> (*mut std::ffi::c_void, bool) {
        let memory = vec![0u8; size].leak();
        (memory.as_mut_ptr().cast(), false)
    }

    pub fn exclude_from_crash_reports(_remove: bool) -> Result<(), i32> {
        Ok(())
    }
}
