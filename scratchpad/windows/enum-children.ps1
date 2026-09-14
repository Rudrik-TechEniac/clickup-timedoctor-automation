Add-Type @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public class EnumHelper {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool EnumChildWindows(IntPtr hwndParent, EnumWindowsProc lpEnumFunc, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);

    [DllImport("user32.dll")]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

    public static List<string> Dump(IntPtr parent) {
        var results = new List<string>();
        EnumWindowsProc cb = (hWnd, lParam) => {
            var cls = new StringBuilder(256);
            GetClassName(hWnd, cls, 256);
            var txt = new StringBuilder(256);
            GetWindowText(hWnd, txt, 256);
            results.Add(hWnd + " | " + cls + " | " + txt);
            return true;
        };
        EnumChildWindows(parent, cb, IntPtr.Zero);
        return results;
    }
}
"@

[EnumHelper]::Dump([IntPtr]66908)
