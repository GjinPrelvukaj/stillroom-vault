using System.Runtime.InteropServices;

namespace Stillroom.Platform;

/// <summary>The emergency kit's pages, printed (the Mac's `KitPrint`): one per piece, black on white, saying what it is
/// and what to do with it. Drawn straight to the printer with Windows' own printing, never saved as a document; the
/// print spooler keeps its own copy only while the job prints.</summary>
internal static unsafe partial class KitPrinter
{
    /// <summary>Asks which printer, then prints, on a thread of its own: Windows' print dialog holds whichever thread
    /// asks until it's closed, and the window's must stay free to lock (the hot key, auto-lock, Windows locking).
    /// `stillWanted` is asked once a printer is chosen: false (the vault locked meanwhile) prints nothing. False when
    /// it was cancelled.</summary>
    public static Task<bool> PrintAsync(IntPtr owner, IReadOnlyList<string> pieces, int threshold, Func<bool> stillWanted)
    {
        var done = new TaskCompletionSource<bool>();
        var thread = new Thread(() =>
        {
            try { done.SetResult(Print(owner, pieces, threshold, stillWanted)); }
            catch (Exception e) { done.SetException(e); }
        });
        thread.SetApartmentState(ApartmentState.STA);
        thread.IsBackground = true;
        thread.Start();
        return done.Task;
    }

    private static bool Print(IntPtr owner, IReadOnlyList<string> pieces, int threshold, Func<bool> stillWanted)
    {
        var dialog = new PRINTDLGW
        {
            lStructSize = (uint)sizeof(PRINTDLGW),
            hwndOwner = owner,
            Flags = PD_RETURNDC | PD_NOPAGENUMS | PD_NOSELECTION | PD_USEDEVMODECOPIESANDCOLLATE,
            nCopies = 1,
        };
        if (!PrintDlgW(&dialog) || dialog.hDC == IntPtr.Zero) return false;
        var dc = dialog.hDC;
        try
        {
            if (!stillWanted()) return false;
            fixed (char* name = "Stillroom emergency kit")
            {
                var doc = new DOCINFOW { cbSize = sizeof(DOCINFOW), lpszDocName = name };
                if (StartDocW(dc, &doc) <= 0) return false;
            }
            var made = DateTime.Now.ToString("d MMMM yyyy");
            for (var i = 0; i < pieces.Count; i++)
            {
                StartPage(dc);
                DrawPage(dc, pieces[i], i + 1, pieces.Count, threshold, made);
                EndPage(dc);
            }
            EndDoc(dc);
            return true;
        }
        finally
        {
            DeleteDC(dc);
            if (dialog.hDevMode != IntPtr.Zero) GlobalFree(dialog.hDevMode);
            if (dialog.hDevNames != IntPtr.Zero) GlobalFree(dialog.hDevNames);
        }
    }

    private static void DrawPage(IntPtr dc, string code, int number, int count, int threshold, string made)
    {
        var width = GetDeviceCaps(dc, HORZRES);
        var height = GetDeviceCaps(dc, VERTRES);
        var dpi = GetDeviceCaps(dc, LOGPIXELSY);
        int Points(double points) => (int)(points * dpi / 72);
        var margin = Points(56);
        var left = margin;
        var right = width - margin;
        var y = margin;

        // Writes `text` from the current line down, wrapped to the page's width; moves the line on past it.
        void Write(string text, double size, int weight = 400, string face = "Segoe UI", uint color = 0x000000, int gapAfter = 0)
        {
            var font = CreateFontW(-Points(size), 0, 0, 0, weight, 0, 0, 0, 1, 0, 0, 5, 0, face);
            var old = SelectObject(dc, font);
            SetTextColor(dc, color);
            SetBkMode(dc, TRANSPARENT);
            var box = new RECT { left = left, top = y, right = right, bottom = height };
            fixed (char* t = text)
            {
                DrawTextW(dc, t, text.Length, &box, DT_WORDBREAK | DT_CALCRECT);
                DrawTextW(dc, t, text.Length, &box, DT_WORDBREAK);
            }
            y = box.bottom + Points(gapAfter);
            SelectObject(dc, old);
            DeleteObject(font);
        }

        Write("VAULT EMERGENCY KIT", 11, 600, color: 0x808080, gapAfter: 6);
        Write($"Piece {number} of {count}", 30, 700, gapAfter: 6);
        Write($"Any {threshold} of the {count} pieces together open the vault. This piece on its own opens nothing.", 13, gapAfter: 22);

        // The piece itself, in a box.
        var boxTop = y;
        y += Points(18);
        var codeFont = CreateFontW(-Points(17), 0, 0, 0, 600, 0, 0, 0, 1, 0, 0, 5, 0, "Consolas");
        var oldFont = SelectObject(dc, codeFont);
        var line = new RECT { left = left, top = y, right = right, bottom = y + Points(24) };
        fixed (char* t = code) DrawTextW(dc, t, code.Length, &line, DT_CENTER | DT_SINGLELINE);
        SelectObject(dc, oldFont);
        DeleteObject(codeFont);
        y = line.bottom + Points(18);
        var pen = CreatePen(0, Math.Max(1, Points(1.5)), 0x000000);
        var oldPen = SelectObject(dc, pen);
        var oldBrush = SelectObject(dc, GetStockObject(NULL_BRUSH));
        RoundRect(dc, left, boxTop, right, y, Points(8), Points(8));
        SelectObject(dc, oldBrush);
        SelectObject(dc, oldPen);
        DeleteObject(pen);
        y += Points(22);

        Write("How to use it", 14, 600, gapAfter: 8);
        Write("1.  On the computer with Stillroom, open Stillroom and choose Use Emergency Kit on the lock screen.", 12.5, gapAfter: 8);
        Write($"2.  Type in this piece and {(threshold == 2 ? "one other" : $"{threshold - 1} others")}. Capitals, dashes and spaces don't matter.", 12.5, gapAfter: 8);
        Write("3.  Choose a new password for the vault when asked.", 12.5, gapAfter: 8);
        Write("If Stillroom isn't available, the free open-source tool stillroom-open opens the vault with the same pieces (see tools/stillroom-open.py in Stillroom's source).", 12.5, color: 0x808080, gapAfter: 22);
        Write("Keep it safe", 14, 600, gapAfter: 8);
        Write("Somewhere you'd keep a will or a passport: a safe, a lockbox, with your lawyer's papers. Don't photograph it or keep it on a computer or phone.", 12.5);

        // The foot of the page: who it was given to, and when it was made.
        y = height - margin - Points(16);
        Write("Given to: ________________________________", 12.5);
        y = height - margin - Points(16);
        var foot = CreateFontW(-Points(11), 0, 0, 0, 400, 0, 0, 0, 1, 0, 0, 5, 0, "Segoe UI");
        var oldFoot = SelectObject(dc, foot);
        SetTextColor(dc, 0x808080);
        var stamp = $"Made {made}";
        var at = new RECT { left = left, top = y, right = right, bottom = y + Points(16) };
        fixed (char* t = stamp) DrawTextW(dc, t, stamp.Length, &at, DT_RIGHT | DT_SINGLELINE);
        SelectObject(dc, oldFoot);
        DeleteObject(foot);
    }

    private const uint PD_RETURNDC = 0x100;
    private const uint PD_NOSELECTION = 0x4;
    private const uint PD_NOPAGENUMS = 0x8;
    private const uint PD_USEDEVMODECOPIESANDCOLLATE = 0x40000;
    private const int HORZRES = 8, VERTRES = 10, LOGPIXELSY = 90;
    private const int TRANSPARENT = 1;
    private const int NULL_BRUSH = 5;
    private const uint DT_CENTER = 0x1, DT_RIGHT = 0x2, DT_SINGLELINE = 0x20, DT_WORDBREAK = 0x10, DT_CALCRECT = 0x400;

    [StructLayout(LayoutKind.Sequential)]
    private struct PRINTDLGW
    {
        public uint lStructSize;
        public IntPtr hwndOwner;
        public IntPtr hDevMode;
        public IntPtr hDevNames;
        public IntPtr hDC;
        public uint Flags;
        public ushort nFromPage, nToPage, nMinPage, nMaxPage, nCopies;
        public IntPtr hInstance;
        public IntPtr lCustData;
        public IntPtr lpfnPrintHook;
        public IntPtr lpfnSetupHook;
        public IntPtr lpPrintTemplateName;
        public IntPtr lpSetupTemplateName;
        public IntPtr hPrintTemplate;
        public IntPtr hSetupTemplate;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct DOCINFOW
    {
        public int cbSize;
        public char* lpszDocName;
        public char* lpszOutput;
        public char* lpszDatatype;
        public uint fwType;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct RECT { public int left, top, right, bottom; }

    [LibraryImport("comdlg32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool PrintDlgW(PRINTDLGW* dialog);
    [LibraryImport("gdi32.dll")] private static partial int StartDocW(IntPtr dc, DOCINFOW* doc);
    [LibraryImport("gdi32.dll")] private static partial int StartPage(IntPtr dc);
    [LibraryImport("gdi32.dll")] private static partial int EndPage(IntPtr dc);
    [LibraryImport("gdi32.dll")] private static partial int EndDoc(IntPtr dc);
    [LibraryImport("gdi32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool DeleteDC(IntPtr dc);
    [LibraryImport("gdi32.dll")] private static partial int GetDeviceCaps(IntPtr dc, int index);
    [LibraryImport("gdi32.dll", StringMarshalling = StringMarshalling.Utf16)]
    private static partial IntPtr CreateFontW(int height, int width, int escapement, int orientation, int weight, uint italic, uint underline, uint strikeOut, uint charSet, uint outPrecision, uint clipPrecision, uint quality, uint pitchAndFamily, string face);
    [LibraryImport("gdi32.dll")] private static partial IntPtr SelectObject(IntPtr dc, IntPtr thing);
    [LibraryImport("gdi32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool DeleteObject(IntPtr thing);
    [LibraryImport("gdi32.dll")] private static partial uint SetTextColor(IntPtr dc, uint color);
    [LibraryImport("gdi32.dll")] private static partial int SetBkMode(IntPtr dc, int mode);
    [LibraryImport("gdi32.dll")] private static partial IntPtr CreatePen(int style, int width, uint color);
    [LibraryImport("gdi32.dll")] private static partial IntPtr GetStockObject(int index);
    [LibraryImport("gdi32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool RoundRect(IntPtr dc, int left, int top, int right, int bottom, int width, int height);
    [LibraryImport("user32.dll")] private static partial int DrawTextW(IntPtr dc, char* text, int count, RECT* rect, uint format);
    [LibraryImport("kernel32.dll")] private static partial IntPtr GlobalFree(IntPtr memory);
}
