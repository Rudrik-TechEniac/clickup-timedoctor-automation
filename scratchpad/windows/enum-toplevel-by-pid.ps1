param([int]$TargetPid)

Add-Type @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public class WinEnum {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);

    [DllImport("user32.dll")]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    public static List<string> FindByPid(int targetPid) {
        var results = new List<string>();
        EnumWindowsProc cb = (hWnd, lParam) => {
            uint pid;
            GetWindowThreadProcessId(hWnd, out pid);
            if (pid == (uint)targetPid) {
                var cls = new StringBuilder(256);
                GetClassName(hWnd, cls, 256);
                var txt = new StringBuilder(256);
                GetWindowText(hWnd, txt, 256);
                bool vis = IsWindowVisible(hWnd);
                results.Add(hWnd + " | class=" + cls + " | title='" + txt + "' | visible=" + vis);
            }
            return true;
        };
        EnumWindows(cb, IntPtr.Zero);
        return results;
    }
}
"@

[WinEnum]::FindByPid($TargetPid)
