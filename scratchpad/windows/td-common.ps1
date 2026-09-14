<#
  Shared helpers for coordinate-based Time Doctor automation.
  Key idea: don't scale click coordinates to whatever size the window happens to be -
  FORCE the window to one exact size/position first (SetWindowPos), then every click
  coordinate is a fixed, known offset. This makes it independent of the machine's
  screen resolution, DPI setting, or whatever size the user last left the window at.
#>

Add-Type @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public class TDAuto {
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, UIntPtr dwExtraInfo);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
    [DllImport("user32.dll")] public static extern int GetSystemMetrics(int nIndex);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    public const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
    public const uint MOUSEEVENTF_LEFTUP = 0x0004;
    public const int SM_CXSCREEN = 0;
    public const int SM_CYSCREEN = 1;
    public const uint SWP_NOZORDER = 0x0004;
    public const uint SWP_SHOWWINDOW = 0x0040;
    public static readonly IntPtr HWND_TOP = IntPtr.Zero;

    public struct RECT { public int Left, Top, Right, Bottom; }

    public static void ClickAt(int x, int y) {
        SetCursorPos(x, y);
        System.Threading.Thread.Sleep(80);
        mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, UIntPtr.Zero);
        System.Threading.Thread.Sleep(60);
        mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, UIntPtr.Zero);
    }

    public static List<IntPtr> FindByPidWithTitleContaining(int targetPid, string mustContain) {
        var results = new List<IntPtr>();
        EnumWindowsProc cb = (hWnd, lParam) => {
            uint pid;
            GetWindowThreadProcessId(hWnd, out pid);
            if (pid == (uint)targetPid) {
                var txt = new StringBuilder(256);
                GetWindowText(hWnd, txt, 256);
                if (txt.ToString().Contains(mustContain)) results.Add(hWnd);
            }
            return true;
        };
        EnumWindows(cb, IntPtr.Zero);
        return results;
    }
}
"@ -ErrorAction SilentlyContinue
Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue

[TDAuto]::SetProcessDPIAware() | Out-Null

# The exact, fixed window size this automation is calibrated against.
# Every click coordinate below assumes the window is EXACTLY this size -
# no proportional scaling, no guessing.
$Script:TD_WIN_W = 1060
$Script:TD_WIN_H = 880
$Script:TD_WIN_X = 40   # fixed on-screen position we force the window to
$Script:TD_WIN_Y = 40

# Pixel offsets from the window's top-left corner, measured against the
# TD_WIN_W x TD_WIN_H layout. Fixed numbers now, not fractions - safe because
# we guarantee the window is exactly this size before every click.
$Script:TD_ADD_TASK_FIELD    = @{ X = 450; Y = 232 }
$Script:TD_ADD_START_BUTTON  = @{ X = 996; Y = 232 }
$Script:TD_STOP_BUTTON       = @{ X = 996; Y = 137 }

function Find-TimeDoctorDashboardHandle {
    $procs = Get-Process | Where-Object { $_.ProcessName -match 'Time Doctor' }
    foreach ($proc in $procs) {
        $matches = [TDAuto]::FindByPidWithTitleContaining($proc.Id, "Company Time")
        if ($matches.Count -gt 0) { return $matches[0] }
    }
    return [IntPtr]::Zero
}

function Set-TimeDoctorWindowGeometry {
    param([IntPtr]$Handle)

    $screenW = [TDAuto]::GetSystemMetrics([TDAuto]::SM_CXSCREEN)
    $screenH = [TDAuto]::GetSystemMetrics([TDAuto]::SM_CYSCREEN)
    if (($Script:TD_WIN_X + $Script:TD_WIN_W) -gt $screenW -or ($Script:TD_WIN_Y + $Script:TD_WIN_H) -gt $screenH) {
        throw "Screen resolution ($screenW x $screenH) is too small to fit the calibrated Time Doctor window size ($($Script:TD_WIN_W) x $($Script:TD_WIN_H) at offset $($Script:TD_WIN_X),$($Script:TD_WIN_Y)). Re-calibrate with smaller values for this machine."
    }

    [TDAuto]::ShowWindowAsync($Handle, 9) | Out-Null   # SW_RESTORE (undo minimize/maximize first)
    Start-Sleep -Milliseconds 300
    [TDAuto]::SetWindowPos($Handle, [TDAuto]::HWND_TOP, $Script:TD_WIN_X, $Script:TD_WIN_Y, $Script:TD_WIN_W, $Script:TD_WIN_H, [TDAuto]::SWP_SHOWWINDOW) | Out-Null
    Start-Sleep -Milliseconds 300
    [TDAuto]::SetForegroundWindow($Handle) | Out-Null
    Start-Sleep -Milliseconds 400

    # Verify the resize actually took (some apps clamp to a min/max size - if so, this
    # automation's fixed offsets are no longer safe to use blindly).
    $rect = New-Object TDAuto+RECT
    [TDAuto]::GetWindowRect($Handle, [ref]$rect) | Out-Null
    $actualW = $rect.Right - $rect.Left
    $actualH = $rect.Bottom - $rect.Top
    if ($actualW -ne $Script:TD_WIN_W -or $actualH -ne $Script:TD_WIN_H) {
        Write-Warning "Window did not resize to the exact calibrated size (got ${actualW}x${actualH}, wanted $($Script:TD_WIN_W)x$($Script:TD_WIN_H)). Clicks may miss."
    }
    return $rect
}

function Get-TimeDoctorScreenPoint {
    param([hashtable]$Offset, $Rect)
    return @{ X = $Rect.Left + $Offset.X; Y = $Rect.Top + $Offset.Y }
}
