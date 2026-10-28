//! Typing a secret on a desktop of its own (windows/PORT.md, "Keyloggers"): the Windows counterpart of the Mac's Secure
//! Keyboard Entry, as far as Windows allows. A second desktop is made, a small prompt is put on it, and the screen is
//! switched to it; what's typed there never passes the desktop other programs' keyboard hooks watch. It's the
//! technique behind the Windows admin prompt and KeePass's "Enter master key on secure desktop". For the password, the
//! recovery key, kit pieces and the decoy password.
//!
//! What's typed is read straight into memory that's wiped, and the box is cleared before the prompt goes. The screen
//! always comes back: on OK, on Cancel or Escape, after two minutes untouched, and if anything inside goes wrong.
//!
//! What it doesn't do: protect typing once the vault is open, or stop software that already runs with your rights from
//! reading the second desktop too. As agreed for the product: "Typing is protected from keyloggers on the unlock screen.
//! Once the vault is open, Stillroom can't stop software already running on your PC from reading keystrokes."

use zeroize::Zeroizing;

/// What to ask for.
pub struct Prompt<'a> {
    /// The prompt's title: "Stillroom".
    pub title: &'a str,
    /// The words above the box: "Password for your vault".
    pub message: &'a str,
    /// Several lines, shown as typed (kit pieces, a piece per line); otherwise one line, hidden as dots.
    pub multiline: bool,
}

/// How long the prompt waits before it gives up and the screen comes back.
pub const GIVE_UP_AFTER_SECONDS: u32 = 120;

/// Asks on a desktop of its own. Gives what was typed, or None when it was cancelled (or timed out).
pub fn ask(prompt: &Prompt) -> std::io::Result<Option<Zeroizing<String>>> {
    windows::ask(prompt, true, None).map(|(typed, _)| typed)
}

#[doc(hidden)]
/// Tests only: the same prompt on its own desktop, without switching the screen to it, typed into by the test itself.
/// `typed` None presses Cancel. Gives the result and whether the prompt really was on the other desktop.
pub fn ask_unseen_for_tests(prompt: &Prompt, typed: Option<&str>) -> std::io::Result<(Option<Zeroizing<String>>, bool)> {
    windows::ask(prompt, false, Some(typed.map(str::to_owned)))
}

#[cfg(windows)]
mod windows {
    use std::cell::RefCell;
    use std::io;

    use windows_sys::Win32::Foundation::{HWND, LPARAM, LRESULT, WPARAM};
    use windows_sys::Win32::Graphics::Gdi::{GetStockObject, DEFAULT_GUI_FONT};
    use windows_sys::Win32::System::LibraryLoader::GetModuleHandleW;
    use windows_sys::Win32::System::StationsAndDesktops::{
        CloseDesktop, CreateDesktopW, GetThreadDesktop, OpenInputDesktop, SetThreadDesktop, SwitchDesktop, DESKTOP_CREATEMENU,
        DESKTOP_CREATEWINDOW, DESKTOP_READOBJECTS, DESKTOP_SWITCHDESKTOP, DESKTOP_WRITEOBJECTS, HDESK,
    };
    use windows_sys::Win32::System::Threading::GetCurrentThreadId;
    use windows_sys::Win32::UI::Input::KeyboardAndMouse::SetFocus;
    use windows_sys::Win32::UI::WindowsAndMessaging::*;
    use zeroize::{Zeroize, Zeroizing};

    use super::{Prompt, GIVE_UP_AFTER_SECONDS};

    const ID_OK: u16 = 1;
    const ID_CANCEL: u16 = 2;
    const ID_GIVE_UP: usize = 7;
    /// Fixed Win32 values from parts of the API this crate doesn't otherwise need (winuser.h).
    const EM_EMPTYUNDOBUFFER: u32 = 0x00CD;
    const COLOR_WINDOW: i32 = 5;

    fn wide(text: &str) -> Vec<u16> {
        text.encode_utf16().chain(Some(0)).collect()
    }

    /// The prompt's state, on its own thread.
    struct Asking {
        edit: HWND,
        typed: Option<Zeroizing<String>>,
        done: bool,
        /// The desktop to switch back to, or null when the screen wasn't switched.
        back: HDESK,
    }

    thread_local! {
        static ASKING: RefCell<Asking> = const { RefCell::new(Asking { edit: std::ptr::null_mut(), typed: None, done: false, back: std::ptr::null_mut() }) };
    }

    /// The prompt is ending: the screen goes back while the prompt is still the window in front. Windows refuses the
    /// switch to a process with no window left on the screen it's showing, so waiting until the prompt is gone left
    /// the screen on the empty desktop.
    unsafe fn finish(window: HWND) {
        let back = ASKING.with(|a| {
            let mut a = a.borrow_mut();
            a.done = true;
            a.back
        });
        if !back.is_null() {
            SwitchDesktop(back);
        }
        DestroyWindow(window);
    }

    /// The box's text, read into wiped memory, then the box cleared.
    unsafe fn take_text(edit: HWND) -> Zeroizing<String> {
        let length = GetWindowTextLengthW(edit).max(0) as usize;
        let mut buffer = Zeroizing::new(vec![0u16; length + 1]);
        let read = GetWindowTextW(edit, buffer.as_mut_ptr(), buffer.len() as i32).max(0) as usize;
        let text = Zeroizing::new(String::from_utf16_lossy(&buffer[..read]));
        let empty = [0u16];
        SetWindowTextW(edit, empty.as_ptr());
        SendMessageW(edit, EM_EMPTYUNDOBUFFER, 0, 0);
        text
    }

    unsafe extern "system" fn window_proc(window: HWND, message: u32, w: WPARAM, l: LPARAM) -> LRESULT {
        match message {
            WM_COMMAND => {
                let id = (w & 0xFFFF) as u16;
                if id == ID_OK || id == ID_CANCEL {
                    ASKING.with(|a| {
                        let mut a = a.borrow_mut();
                        if id == ID_OK {
                            a.typed = Some(take_text(a.edit));
                        } else {
                            take_text(a.edit);
                        }
                    });
                    finish(window);
                    return 0;
                }
                DefWindowProcW(window, message, w, l)
            }
            WM_TIMER | WM_CLOSE => {
                ASKING.with(|a| {
                    take_text(a.borrow().edit);
                });
                finish(window);
                0
            }
            WM_DESTROY => {
                PostQuitMessage(0);
                0
            }
            _ => DefWindowProcW(window, message, w, l),
        }
    }

    /// The desktop handles, the screen switched back and both closed however this ends.
    struct Desktops {
        own: HDESK,
        before: HDESK,
        switched: bool,
    }

    impl Drop for Desktops {
        fn drop(&mut self) {
            // SAFETY: both handles came from this module and are closed once, here.
            unsafe {
                // The prompt switched back as it ended; this is for a prompt that never got that far.
                if self.switched {
                    SwitchDesktop(self.before);
                }
                if !self.before.is_null() {
                    CloseDesktop(self.before);
                }
                CloseDesktop(self.own);
            }
        }
    }

    pub fn ask(prompt: &Prompt, switch: bool, test_typing: Option<Option<String>>) -> io::Result<(Option<Zeroizing<String>>, bool)> {
        let name = wide(&format!("Stillroom-{}", uuid::Uuid::new_v4().simple()));
        let access = DESKTOP_CREATEWINDOW | DESKTOP_CREATEMENU | DESKTOP_READOBJECTS | DESKTOP_WRITEOBJECTS | DESKTOP_SWITCHDESKTOP;
        // SAFETY: plain Win32 calls; the handles are owned by `Desktops`, which closes them.
        let desktops = unsafe {
            let own = CreateDesktopW(name.as_ptr(), std::ptr::null(), std::ptr::null(), 0, access, std::ptr::null());
            if own.is_null() {
                return Err(io::Error::last_os_error());
            }
            let before = OpenInputDesktop(0, 0, DESKTOP_SWITCHDESKTOP);
            Desktops { own, before, switched: switch }
        };
        let own = desktops.own as usize;
        let back = if switch { desktops.before as usize } else { 0 };
        let (title, message, multiline) = (prompt.title.to_owned(), prompt.message.to_owned(), prompt.multiline);

        // The prompt runs on a thread of its own: only a thread with no windows yet can move to another desktop.
        let result = std::thread::scope(|scope| {
            scope
                .spawn(move || unsafe { run(own as HDESK, back as HDESK, &title, &message, multiline, switch, test_typing) })
                .join()
                .unwrap_or_else(|_| Err(io::Error::other("the prompt stopped")))
        });
        drop(desktops);
        result
    }

    /// The prompt, on this thread, on `desktop`; the screen goes back to `back` (unless null) as it ends. Gives what was
    /// typed and whether it was on `desktop`.
    #[allow(clippy::too_many_arguments)]
    unsafe fn run(
        desktop: HDESK,
        back: HDESK,
        title: &str,
        message: &str,
        multiline: bool,
        switch: bool,
        test_typing: Option<Option<String>>,
    ) -> io::Result<(Option<Zeroizing<String>>, bool)> {
        if SetThreadDesktop(desktop) == 0 {
            return Err(io::Error::last_os_error());
        }
        let on_own_desktop = GetThreadDesktop(GetCurrentThreadId()) == desktop;
        let instance = GetModuleHandleW(std::ptr::null());
        let class = wide("StillroomSecurePrompt");
        let class_info = WNDCLASSEXW {
            cbSize: std::mem::size_of::<WNDCLASSEXW>() as u32,
            lpfnWndProc: Some(window_proc),
            hInstance: instance,
            lpszClassName: class.as_ptr(),
            hCursor: LoadCursorW(std::ptr::null_mut(), IDC_ARROW),
            hbrBackground: (COLOR_WINDOW + 1) as usize as _,
            ..std::mem::zeroed()
        };
        // Registered once per process; a second registration fails harmlessly.
        RegisterClassExW(&class_info);

        let (width, height) = (440, if multiline { 300 } else { 170 });
        let x = (GetSystemMetrics(SM_CXSCREEN) - width) / 2;
        let y = (GetSystemMetrics(SM_CYSCREEN) - height) / 2;
        let title = wide(title);
        let window = CreateWindowExW(
            WS_EX_CONTROLPARENT | WS_EX_TOPMOST,
            class.as_ptr(),
            title.as_ptr(),
            WS_POPUP | WS_CAPTION | WS_SYSMENU,
            x,
            y,
            width,
            height,
            std::ptr::null_mut(),
            std::ptr::null_mut(),
            instance,
            std::ptr::null(),
        );
        if window.is_null() {
            return Err(io::Error::last_os_error());
        }
        let font = GetStockObject(DEFAULT_GUI_FONT);
        let child = |kind: &str, text: &str, style: u32, ex: u32, x: i32, y: i32, w: i32, h: i32, id: u16| {
            let (kind, text) = (wide(kind), wide(text));
            let made = CreateWindowExW(ex, kind.as_ptr(), text.as_ptr(), WS_CHILD | WS_VISIBLE | style, x, y, w, h, window, id as usize as _, instance, std::ptr::null());
            SendMessageW(made, WM_SETFONT, font as usize, 1);
            made
        };
        child("STATIC", message, 0, 0, 16, 14, width - 40, 36, 0);
        let edit_style = if multiline {
            (ES_MULTILINE | ES_WANTRETURN | ES_AUTOVSCROLL) as u32 | WS_VSCROLL
        } else {
            (ES_PASSWORD | ES_AUTOHSCROLL) as u32
        };
        let edit_height = if multiline { 150 } else { 24 };
        let edit = child("EDIT", "", edit_style | WS_TABSTOP | WS_BORDER, WS_EX_CLIENTEDGE, 16, 52, width - 40, edit_height, 100);
        let buttons = 52 + edit_height + 14;
        child("BUTTON", "OK", BS_DEFPUSHBUTTON as u32 | WS_TABSTOP, 0, width - 200, buttons, 80, 28, ID_OK);
        child("BUTTON", "Cancel", BS_PUSHBUTTON as u32 | WS_TABSTOP, 0, width - 110, buttons, 80, 28, ID_CANCEL);
        ASKING.with(|a| *a.borrow_mut() = Asking { edit, typed: None, done: false, back });
        SetTimer(window, ID_GIVE_UP, GIVE_UP_AFTER_SECONDS * 1000, None);

        ShowWindow(window, SW_SHOW);
        if switch {
            SwitchDesktop(desktop);
        }
        SetForegroundWindow(window);
        SetFocus(edit);

        if let Some(typing) = test_typing {
            match typing {
                Some(text) => {
                    let mut text = wide(&text);
                    SetWindowTextW(edit, text.as_ptr());
                    text.zeroize();
                    PostMessageW(window, WM_COMMAND, ID_OK as usize, 0);
                }
                None => {
                    PostMessageW(window, WM_COMMAND, ID_CANCEL as usize, 0);
                }
            }
        }

        let mut message: MSG = std::mem::zeroed();
        while GetMessageW(&mut message, std::ptr::null_mut(), 0, 0) > 0 {
            // Enter presses OK and Escape Cancel, as in any dialog.
            if IsDialogMessageW(window, &message) == 0 {
                TranslateMessage(&message);
                DispatchMessageW(&message);
            }
            if ASKING.with(|a| a.borrow().done) && IsWindow(window) == 0 {
                break;
            }
        }
        let typed = ASKING.with(|a| a.borrow_mut().typed.take());
        Ok((typed, on_own_desktop))
    }
}

#[cfg(not(windows))]
mod windows {
    use zeroize::Zeroizing;

    use super::Prompt;

    pub fn ask(_prompt: &Prompt, _switch: bool, _test: Option<Option<String>>) -> std::io::Result<(Option<Zeroizing<String>>, bool)> {
        Err(std::io::Error::other("a desktop of its own is Windows only"))
    }
}
