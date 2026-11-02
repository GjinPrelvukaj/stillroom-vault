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

#[doc(hidden)]
/// Tests only: the same prompt drawn on the screen as it is, for `seconds`, then gone; nothing is asked or switched.
/// For looking at how it's drawn (`cargo run --example secure_prompt -- --preview`).
pub fn preview_for_tests(prompt: &Prompt, seconds: u32) -> std::io::Result<()> {
    windows::preview(prompt, seconds)
}

#[cfg(windows)]
mod windows {
    use std::cell::RefCell;
    use std::io;

    use windows_sys::Win32::Foundation::{COLORREF, HWND, LPARAM, LRESULT, RECT, WPARAM};
    use windows_sys::Win32::Graphics::Dwm::{DwmSetWindowAttribute, DWMWA_BORDER_COLOR, DWMWA_WINDOW_CORNER_PREFERENCE};
    use windows_sys::Win32::Graphics::Gdi::*;
    use windows_sys::Win32::System::LibraryLoader::GetModuleHandleW;
    use windows_sys::Win32::System::StationsAndDesktops::{
        CloseDesktop, CreateDesktopW, GetThreadDesktop, OpenInputDesktop, SetThreadDesktop, SwitchDesktop, DESKTOP_CREATEMENU,
        DESKTOP_CREATEWINDOW, DESKTOP_READOBJECTS, DESKTOP_SWITCHDESKTOP, DESKTOP_WRITEOBJECTS, HDESK,
    };
    use windows_sys::Win32::System::Threading::GetCurrentThreadId;
    use windows_sys::Win32::UI::Controls::{DRAWITEMSTRUCT, ODS_FOCUS, ODS_SELECTED};
    use windows_sys::Win32::UI::HiDpi::{GetDpiForSystem, SetThreadDpiAwarenessContext, DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2};
    use windows_sys::Win32::UI::Input::KeyboardAndMouse::{GetFocus, SetFocus};
    use windows_sys::Win32::UI::WindowsAndMessaging::*;
    use zeroize::{Zeroize, Zeroizing};

    use super::{Prompt, GIVE_UP_AFTER_SECONDS};

    const ID_OK: u16 = 1;
    const ID_CANCEL: u16 = 2;
    const ID_EDIT: u16 = 100;
    const ID_GIVE_UP: usize = 7;
    /// Fixed Win32 values from parts of the API this crate doesn't otherwise need (winuser.h, dwmapi.h).
    const EM_EMPTYUNDOBUFFER: u32 = 0x00CD;
    const EM_SETMARGINS: u32 = 0x00D3;
    const EC_LEFTMARGIN_RIGHTMARGIN: usize = 0x0003;
    const EN_SETFOCUS: u16 = 0x0100;
    const EN_KILLFOCUS: u16 = 0x0200;
    const DWMWCP_ROUND: u32 = 2;

    /// Stillroom's colours (the app's dark appearance, App.xaml), as Windows writes them: 0x00BBGGRR.
    const fn rgb(r: u8, g: u8, b: u8) -> COLORREF {
        r as u32 | (g as u32) << 8 | (b as u32) << 16
    }
    const CARD: COLORREF = rgb(0x17, 0x15, 0x1F);
    const FIELD: COLORREF = rgb(0x0E, 0x0D, 0x13);
    const FIELD_EDGE: COLORREF = rgb(0x3A, 0x35, 0x4D);
    const VIOLET: COLORREF = rgb(0xB0, 0x8C, 0xFF);
    const VIOLET_PRESSED: COLORREF = rgb(0x9A, 0x73, 0xF0);
    const ON_VIOLET: COLORREF = rgb(0x14, 0x10, 0x1F);
    const SECOND: COLORREF = rgb(0x2B, 0x28, 0x36);
    const SECOND_PRESSED: COLORREF = rgb(0x22, 0x20, 0x2C);
    const INK: COLORREF = rgb(0xF4, 0xF2, 0xF8);
    const QUIET: COLORREF = rgb(0x9C, 0x97, 0xAB);
    const BACK_TOP: COLORREF = rgb(0x07, 0x06, 0x0A);
    const BACK_BOTTOM: COLORREF = rgb(0x1E, 0x16, 0x36);

    /// What the screen says under the box, in every prompt.
    const REASSURANCE: &str = "Typed on a screen of its own, out of other programs' reach.";

    fn wide(text: &str) -> Vec<u16> {
        text.encode_utf16().chain(Some(0)).collect()
    }

    /// Where everything sits on the card, in pixels at the screen's scale.
    #[derive(Clone, Copy)]
    struct Layout {
        width: i32,
        height: i32,
        eyebrow: RECT,
        lock: RECT,
        message: RECT,
        field: RECT,
        note: RECT,
        ok: RECT,
        cancel: RECT,
        radius: i32,
        /// The eyebrow's letters spaced out, as the app's are.
        spacing: i32,
    }

    impl Layout {
        fn new(scale: f64, multiline: bool) -> Layout {
            let px = |v: i32| (v as f64 * scale).round() as i32;
            let rect = |left: i32, top: i32, right: i32, bottom: i32| RECT { left: px(left), top: px(top), right: px(right), bottom: px(bottom) };
            let (width, pad) = (460, 28);
            let field_bottom = if multiline { 258 } else { 150 };
            let note_bottom = field_bottom + 30;
            let buttons = (note_bottom + 16, note_bottom + 52);
            Layout {
                width: px(width),
                height: px(buttons.1 + 26),
                lock: rect(pad, 24, pad + 20, 46),
                eyebrow: rect(pad + 28, 26, width - pad, 46),
                message: rect(pad, 56, width - pad, 100),
                field: rect(pad, 108, width - pad, field_bottom),
                note: rect(pad, field_bottom + 10, width - pad, note_bottom),
                ok: rect(width - pad - 104, buttons.0, width - pad, buttons.1),
                cancel: rect(width - pad - 104 - 10 - 104, buttons.0, width - pad - 104 - 10, buttons.1),
                radius: px(10),
                spacing: px(1).max(1),
            }
        }
    }

    /// The fonts and brushes the prompt draws with, made for the screen's scale and let go of as it ends.
    struct Look {
        eyebrow: HFONT,
        message: HFONT,
        field: HFONT,
        small: HFONT,
        button: HFONT,
        icons: HFONT,
        field_brush: HBRUSH,
    }

    impl Look {
        unsafe fn new(scale: f64) -> Look {
            let font = |points: f64, weight: i32, face: &str| {
                let face = wide(face);
                CreateFontW(-((points * 96.0 / 72.0 * scale).round() as i32), 0, 0, 0, weight, 0, 0, 0, DEFAULT_CHARSET as u32,
                    OUT_DEFAULT_PRECIS as u32, CLIP_DEFAULT_PRECIS as u32, CLEARTYPE_QUALITY as u32, DEFAULT_PITCH as u32, face.as_ptr())
            };
            Look {
                eyebrow: font(8.0, FW_SEMIBOLD as i32, "Segoe UI"),
                message: font(13.0, FW_SEMIBOLD as i32, "Segoe UI"),
                field: font(11.0, FW_NORMAL as i32, "Segoe UI"),
                small: font(9.0, FW_NORMAL as i32, "Segoe UI"),
                button: font(10.0, FW_SEMIBOLD as i32, "Segoe UI"),
                // Windows 11's symbols, the same the app's own glyphs come from.
                icons: font(13.0, FW_NORMAL as i32, "Segoe Fluent Icons"),
                field_brush: CreateSolidBrush(FIELD),
            }
        }
    }

    impl Drop for Look {
        fn drop(&mut self) {
            // SAFETY: each was made by `Look::new` and is deleted once, here.
            unsafe {
                for font in [self.eyebrow, self.message, self.field, self.small, self.button, self.icons] {
                    DeleteObject(font);
                }
                DeleteObject(self.field_brush);
            }
        }
    }

    /// The prompt's state, on its own thread.
    struct Asking {
        edit: HWND,
        typed: Option<Zeroizing<String>>,
        done: bool,
        /// The desktop to switch back to, or null when the screen wasn't switched.
        back: HDESK,
        title: Vec<u16>,
        message: Vec<u16>,
        layout: Option<Layout>,
        look: Option<Look>,
        /// The box has the keyboard: its edge lights up.
        typing: bool,
    }

    thread_local! {
        static ASKING: RefCell<Asking> = const { RefCell::new(Asking {
            edit: std::ptr::null_mut(), typed: None, done: false, back: std::ptr::null_mut(), title: Vec::new(),
            message: Vec::new(), layout: None, look: None, typing: false,
        }) };
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

    unsafe fn fill_round(dc: HDC, rect: &RECT, radius: i32, fill: COLORREF, edge: COLORREF) {
        let brush = CreateSolidBrush(fill);
        let pen = CreatePen(PS_SOLID, 1, edge);
        let (old_brush, old_pen) = (SelectObject(dc, brush), SelectObject(dc, pen));
        RoundRect(dc, rect.left, rect.top, rect.right, rect.bottom, radius, radius);
        SelectObject(dc, old_brush);
        SelectObject(dc, old_pen);
        DeleteObject(brush);
        DeleteObject(pen);
    }

    unsafe fn text(dc: HDC, font: HFONT, color: COLORREF, words: &[u16], rect: &RECT, format: u32) {
        let old = SelectObject(dc, font);
        SetTextColor(dc, color);
        SetBkMode(dc, TRANSPARENT as i32);
        let mut rect = *rect;
        // `words` ends in a NUL, which isn't drawn.
        DrawTextW(dc, words.as_ptr(), words.len() as i32 - 1, &mut rect, format);
        SelectObject(dc, old);
    }

    /// The card: the lock and the title, the question, the box's rounded field, and the line under it.
    unsafe fn paint(window: HWND) {
        let mut ps: PAINTSTRUCT = std::mem::zeroed();
        let dc = BeginPaint(window, &mut ps);
        ASKING.with(|a| {
            let a = a.borrow();
            let (Some(layout), Some(look)) = (a.layout, a.look.as_ref()) else { return };
            let all = RECT { left: 0, top: 0, right: layout.width, bottom: layout.height };
            let card = CreateSolidBrush(CARD);
            FillRect(dc, &all, card);
            DeleteObject(card);
            text(dc, look.icons, VIOLET, &wide("\u{E72E}"), &layout.lock, DT_LEFT | DT_VCENTER | DT_SINGLELINE);
            SetTextCharacterExtra(dc, layout.spacing);
            text(dc, look.eyebrow, VIOLET, &a.title, &layout.eyebrow, DT_LEFT | DT_VCENTER | DT_SINGLELINE);
            SetTextCharacterExtra(dc, 0);
            text(dc, look.message, INK, &a.message, &layout.message, DT_LEFT | DT_WORDBREAK);
            fill_round(dc, &layout.field, layout.radius, FIELD, if a.typing { VIOLET } else { FIELD_EDGE });
            text(dc, look.small, QUIET, &wide(REASSURANCE), &layout.note, DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS);
        });
        EndPaint(window, &ps);
    }

    /// OK in Stillroom's violet, Cancel in grey glass, each a rounded pill; a thin ring when it has the keyboard.
    unsafe fn draw_button(item: &DRAWITEMSTRUCT) {
        let ok = item.CtlID == ID_OK as u32;
        let pressed = item.itemState & ODS_SELECTED != 0;
        let (fill, ink) = match (ok, pressed) {
            (true, false) => (VIOLET, ON_VIOLET),
            (true, true) => (VIOLET_PRESSED, ON_VIOLET),
            (false, false) => (SECOND, INK),
            (false, true) => (SECOND_PRESSED, INK),
        };
        let dc = item.hDC;
        let all = item.rcItem;
        let card = CreateSolidBrush(CARD);
        FillRect(dc, &all, card);
        DeleteObject(card);
        let radius = (all.bottom - all.top) / 2 * 2;
        let edge = if item.itemState & ODS_FOCUS != 0 { INK } else { fill };
        fill_round(dc, &all, radius, fill, edge);
        ASKING.with(|a| {
            if let Some(look) = a.borrow().look.as_ref() {
                let label = wide(if ok { "OK" } else { "Cancel" });
                text(dc, look.button, ink, &label, &all, DT_CENTER | DT_VCENTER | DT_SINGLELINE);
            }
        });
    }

    unsafe extern "system" fn window_proc(window: HWND, message: u32, w: WPARAM, l: LPARAM) -> LRESULT {
        match message {
            WM_COMMAND => {
                let (id, event) = ((w & 0xFFFF) as u16, ((w >> 16) & 0xFFFF) as u16);
                if id == ID_EDIT && (event == EN_SETFOCUS || event == EN_KILLFOCUS) {
                    let field = ASKING.with(|a| {
                        let mut a = a.borrow_mut();
                        a.typing = event == EN_SETFOCUS;
                        a.layout.map(|l| l.field)
                    });
                    if let Some(field) = field {
                        InvalidateRect(window, &field, 0);
                    }
                    return 0;
                }
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
            WM_PAINT => {
                paint(window);
                0
            }
            WM_ERASEBKGND => 1,
            WM_DRAWITEM => {
                draw_button(&*(l as *const DRAWITEMSTRUCT));
                1
            }
            // The box in the field's dark, with the ink's colour.
            WM_CTLCOLOREDIT => {
                let dc = w as HDC;
                SetTextColor(dc, INK);
                SetBkColor(dc, FIELD);
                ASKING.with(|a| a.borrow().look.as_ref().map_or(0, |look| look.field_brush as LRESULT))
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

    /// The screen behind the card, edge to edge on every monitor: near black, warming to Stillroom's violet at the
    /// bottom, as the app's window is lit from its bottom edge.
    unsafe extern "system" fn backdrop_proc(window: HWND, message: u32, w: WPARAM, l: LPARAM) -> LRESULT {
        match message {
            WM_PAINT => {
                let mut ps: PAINTSTRUCT = std::mem::zeroed();
                let dc = BeginPaint(window, &mut ps);
                let mut all: RECT = std::mem::zeroed();
                GetClientRect(window, &mut all);
                let vertex = |x: i32, y: i32, c: COLORREF| TRIVERTEX {
                    x,
                    y,
                    Red: ((c & 0xFF) as u16) << 8,
                    Green: (((c >> 8) & 0xFF) as u16) << 8,
                    Blue: (((c >> 16) & 0xFF) as u16) << 8,
                    Alpha: 0,
                };
                let vertices = [vertex(all.left, all.top, BACK_TOP), vertex(all.right, all.bottom, BACK_BOTTOM)];
                let rect = GRADIENT_RECT { UpperLeft: 0, LowerRight: 1 };
                GradientFill(dc, vertices.as_ptr(), 2, (&rect as *const GRADIENT_RECT).cast(), 1, GRADIENT_FILL_RECT_V);
                EndPaint(window, &ps);
                0
            }
            WM_ERASEBKGND => 1,
            // Clicked, it gives the keyboard back to the card.
            WM_ACTIVATE | WM_LBUTTONDOWN => {
                let edit = ASKING.with(|a| a.borrow().edit);
                if !edit.is_null() && GetFocus() != edit {
                    SetFocus(edit);
                }
                DefWindowProcW(window, message, w, l)
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
                .spawn(move || unsafe { run(own as HDESK, back as HDESK, &title, &message, multiline, switch, test_typing, GIVE_UP_AFTER_SECONDS) })
                .join()
                .unwrap_or_else(|_| Err(io::Error::other("the prompt stopped")))
        });
        drop(desktops);
        result
    }

    /// Tests only: the prompt on the desktop that's showing, closing itself after `seconds`.
    pub fn preview(prompt: &Prompt, seconds: u32) -> io::Result<()> {
        let (title, message, multiline) = (prompt.title.to_owned(), prompt.message.to_owned(), prompt.multiline);
        std::thread::scope(|scope| {
            scope
                .spawn(move || unsafe {
                    let here = GetThreadDesktop(GetCurrentThreadId());
                    run(here, std::ptr::null_mut(), &title, &message, multiline, false, None, seconds).map(|_| ())
                })
                .join()
                .unwrap_or_else(|_| Err(io::Error::other("the prompt stopped")))
        })
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
        give_up: u32,
    ) -> io::Result<(Option<Zeroizing<String>>, bool)> {
        if SetThreadDesktop(desktop) == 0 {
            return Err(io::Error::last_os_error());
        }
        // Drawn at the screen's own scale, so it's sharp on a high-resolution display rather than blown up and blurred.
        SetThreadDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
        let scale = GetDpiForSystem().max(96) as f64 / 96.0;
        let on_own_desktop = GetThreadDesktop(GetCurrentThreadId()) == desktop;
        let instance = GetModuleHandleW(std::ptr::null());
        let arrow = LoadCursorW(std::ptr::null_mut(), IDC_ARROW);

        // Registered once per process; a second registration fails harmlessly.
        let backdrop_class = wide("StillroomSecureBackdrop");
        RegisterClassExW(&WNDCLASSEXW {
            cbSize: std::mem::size_of::<WNDCLASSEXW>() as u32,
            lpfnWndProc: Some(backdrop_proc),
            hInstance: instance,
            lpszClassName: backdrop_class.as_ptr(),
            hCursor: arrow,
            ..std::mem::zeroed()
        });
        let class = wide("StillroomSecurePrompt");
        RegisterClassExW(&WNDCLASSEXW {
            cbSize: std::mem::size_of::<WNDCLASSEXW>() as u32,
            lpfnWndProc: Some(window_proc),
            hInstance: instance,
            lpszClassName: class.as_ptr(),
            hCursor: arrow,
            ..std::mem::zeroed()
        });

        let empty = wide("");
        let backdrop = CreateWindowExW(
            WS_EX_TOOLWINDOW,
            backdrop_class.as_ptr(),
            empty.as_ptr(),
            WS_POPUP | WS_VISIBLE,
            GetSystemMetrics(SM_XVIRTUALSCREEN),
            GetSystemMetrics(SM_YVIRTUALSCREEN),
            GetSystemMetrics(SM_CXVIRTUALSCREEN),
            GetSystemMetrics(SM_CYVIRTUALSCREEN),
            std::ptr::null_mut(),
            std::ptr::null_mut(),
            instance,
            std::ptr::null(),
        );

        let layout = Layout::new(scale, multiline);
        let look = Look::new(scale);
        let title_text = wide(&title.to_uppercase());
        let window = CreateWindowExW(
            WS_EX_CONTROLPARENT | WS_EX_TOPMOST,
            class.as_ptr(),
            wide(title).as_ptr(),
            WS_POPUP,
            (GetSystemMetrics(SM_CXSCREEN) - layout.width) / 2,
            (GetSystemMetrics(SM_CYSCREEN) - layout.height) / 2,
            layout.width,
            layout.height,
            backdrop,
            std::ptr::null_mut(),
            instance,
            std::ptr::null(),
        );
        if window.is_null() {
            if !backdrop.is_null() {
                DestroyWindow(backdrop);
            }
            return Err(io::Error::last_os_error());
        }
        // Windows 11's rounded corners, and a faint violet edge.
        let round = DWMWCP_ROUND;
        DwmSetWindowAttribute(window, DWMWA_WINDOW_CORNER_PREFERENCE as u32, (&round as *const u32).cast(), 4);
        let edge = FIELD_EDGE;
        DwmSetWindowAttribute(window, DWMWA_BORDER_COLOR as u32, (&edge as *const COLORREF).cast(), 4);

        let child = |kind: &str, style: u32, rect: RECT, id: u16, font: HFONT| {
            let (kind, text) = (wide(kind), wide(""));
            let made = CreateWindowExW(0, kind.as_ptr(), text.as_ptr(), WS_CHILD | WS_VISIBLE | style, rect.left, rect.top,
                rect.right - rect.left, rect.bottom - rect.top, window, id as usize as _, instance, std::ptr::null());
            SendMessageW(made, WM_SETFONT, font as usize, 1);
            made
        };
        // The box sits inside the drawn field, clear of its rounded edge; one line is centred in it.
        let inset = (12.0 * scale) as i32;
        let field = layout.field;
        let line = (24.0 * scale) as i32;
        let box_rect = if multiline {
            RECT { left: field.left + inset, top: field.top + inset / 2 + 2, right: field.right - inset / 2, bottom: field.bottom - inset / 2 }
        } else {
            let top = field.top + (field.bottom - field.top - line) / 2;
            RECT { left: field.left + inset, top, right: field.right - inset, bottom: top + line }
        };
        let edit_style = if multiline {
            // No scroll bar (Windows would draw it white): the pieces fit, and the box still scrolls with the caret.
            (ES_MULTILINE | ES_WANTRETURN | ES_AUTOVSCROLL) as u32
        } else {
            (ES_PASSWORD | ES_AUTOHSCROLL) as u32
        };
        let edit = child("EDIT", edit_style | WS_TABSTOP, box_rect, ID_EDIT, look.field);
        SendMessageW(edit, EM_SETMARGINS, EC_LEFTMARGIN_RIGHTMARGIN, 0);
        child("BUTTON", BS_OWNERDRAW as u32 | WS_TABSTOP, layout.ok, ID_OK, look.button);
        child("BUTTON", BS_OWNERDRAW as u32 | WS_TABSTOP, layout.cancel, ID_CANCEL, look.button);
        ASKING.with(|a| {
            *a.borrow_mut() = Asking {
                edit,
                typed: None,
                done: false,
                back,
                title: title_text,
                message: wide(message),
                layout: Some(layout),
                look: Some(look),
                typing: false,
            }
        });
        SetTimer(window, ID_GIVE_UP, give_up * 1000, None);

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
        if !backdrop.is_null() {
            DestroyWindow(backdrop);
        }
        // The fonts and brushes go with the prompt; what was typed goes to the caller.
        let (typed, look) = ASKING.with(|a| {
            let mut a = a.borrow_mut();
            a.layout = None;
            (a.typed.take(), a.look.take())
        });
        drop(look);
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

    pub fn preview(_prompt: &Prompt, _seconds: u32) -> std::io::Result<()> {
        Err(std::io::Error::other("a desktop of its own is Windows only"))
    }
}
