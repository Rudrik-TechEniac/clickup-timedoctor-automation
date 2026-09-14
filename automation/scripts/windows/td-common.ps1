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
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr hWnd);

    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    public const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
    public const uint MOUSEEVENTF_LEFTUP = 0x0004;
    public const int SM_CXSCREEN = 0;
    public const int SM_CYSCREEN = 1;
    public const uint SWP_NOZORDER = 0x0004;
    public const uint SWP_SHOWWINDOW = 0x0040;
    public static readonly IntPtr HWND_TOP = IntPtr.Zero;

    public struct RECT { public int Left, Top, Right, Bottom; }

    public const uint MOUSEEVENTF_WHEEL = 0x0800;

    public static void ClickAt(int x, int y) {
        SetCursorPos(x, y);
        System.Threading.Thread.Sleep(80);
        mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, UIntPtr.Zero);
        System.Threading.Thread.Sleep(60);
        mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, UIntPtr.Zero);
    }

    // notches: positive scrolls up, negative scrolls down. One notch = 120 (WHEEL_DELTA).
    public static void ScrollAt(int x, int y, int notches) {
        SetCursorPos(x, y);
        System.Threading.Thread.Sleep(50);
        int delta = notches * 120;
        mouse_event(MOUSEEVENTF_WHEEL, 0, 0, unchecked((uint)delta), UIntPtr.Zero);
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
$Script:TD_PROJECT_FIELD     = @{ X = 825; Y = 232 }
$Script:TD_ADD_START_BUTTON  = @{ X = 996; Y = 232 }
$Script:TD_STOP_BUTTON       = @{ X = 996; Y = 137 }

# Left sidebar PROJECTS list under "TD", clicked directly instead of fighting the
# unreliable "Type a Project" autocomplete field (confirmed live: typing there landed
# on the wrong project - "PA" instead of "SENA" - even with keyboard-driven selection).
#
# SELF-CALIBRATING BY FORMULA, not per-project pixel measurement: sidebar rows are
# evenly spaced (measured: ~48px apart), so a row's Y position is computed from
# TD_SIDEBAR_LAST_ROW_Y working UPWARD by how far the target project is from the END
# of TD_SIDEBAR_PROJECT_ORDER. Anchored from the bottom (not the top) deliberately -
# scrolling to the bottom, and the Y of the last row once there, is the exact behavior
# already proven correct through repeated live testing; scrolling to the top instead
# would reveal the FOLDERS section above PROJECTS and land at a different, unverified
# position, so it's not used here even though it seems equally natural.
# TD_WIN_*, X, row height, and last-row offset are app-chrome constants that transfer
# across any machine running the same Time Doctor version - only TD_SIDEBAR_PROJECT_ORDER
# (the actual project names, in the order Time Doctor's sidebar shows them - alphabetical,
# "All" pinned first) is person/company-specific and needs updating per account. Getting
# that list needs no pixel measuring: run td-screenshot-only.ps1 after scrolling to the
# bottom, read the project names off the sidebar top-to-bottom (trivial - Claude can do
# this directly from the screenshot), and replace the array below.
#
# LIMITATION: only reachable if the target project is within the visible window counting
# up from the end (~8 rows tall at this window size) once scrolled to the bottom. A
# project far from the end of a long list isn't reachable by this formula alone - not
# handled; re-measure that specific case manually if it comes up.
$Script:TD_SIDEBAR_X = 180
$Script:TD_SIDEBAR_LAST_ROW_Y = 847   # Y of the last project's row when scrolled to bottom
$Script:TD_SIDEBAR_ROW_HEIGHT = 48
$Script:TD_SIDEBAR_PROJECT_ORDER = @(
    "all", "ai personal", "cp-portal", "eyecentric", "khalil_voice", "pa", "self learning", "sena"
)

$Script:TD_SIDEBAR_SCROLL_TARGET = @{ X = 180; Y = 500 }

# Confirmed live: the sidebar's scroll position is NOT fixed between sessions (it
# carries over whatever the app/user last scrolled to), so TD_SIDEBAR_LAST_ROW_Y is only
# valid immediately after scrolling to one deterministic, known position first. Scrolling
# far past the actual bottom is safe (it just stops at the boundary) and gives that fixed
# reference point regardless of where the sidebar happened to be. Must be called
# immediately before Select-TimeDoctorSidebarProject every time - not once per session -
# since anything else scrolling that pane resets it.
function Reset-TimeDoctorSidebarScroll {
    param([IntPtr]$Handle, $Rect)
    Assert-TimeDoctorForeground -Handle $Handle
    $point = Get-TimeDoctorScreenPoint -Offset $Script:TD_SIDEBAR_SCROLL_TARGET -Rect $Rect
    # Many notches, well beyond any plausible list length, to guarantee hitting bottom.
    [TDAuto]::ScrollAt($point.X, $point.Y, -40)
    Start-Sleep -Milliseconds 500
}

function Select-TimeDoctorSidebarProject {
    param([IntPtr]$Handle, [string]$ProjectName, $Rect)
    $key = $ProjectName.Trim().ToLower()
    $index = [array]::IndexOf($Script:TD_SIDEBAR_PROJECT_ORDER, $key)
    if ($index -lt 0) {
        $available = $Script:TD_SIDEBAR_PROJECT_ORDER -join ", "
        throw "Project '$ProjectName' is not in the known sidebar order: $available. Update TD_SIDEBAR_PROJECT_ORDER in td-common.ps1 with the real project list (read off a td-screenshot-only.ps1 screenshot, top to bottom - no pixel measuring needed) if this project exists but isn't listed."
    }
    $fromEnd = $Script:TD_SIDEBAR_PROJECT_ORDER.Count - 1 - $index
    Reset-TimeDoctorSidebarScroll -Handle $Handle -Rect $Rect
    $offset = @{ X = $Script:TD_SIDEBAR_X; Y = $Script:TD_SIDEBAR_LAST_ROW_Y - ($fromEnd * $Script:TD_SIDEBAR_ROW_HEIGHT) }
    Invoke-TimeDoctorClick -Handle $Handle -Offset $offset -Rect $Rect | Out-Null
    Start-Sleep -Milliseconds 500
}

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

    # CRITICAL SAFETY CHECK: confirmed live (twice) that focus can be elsewhere - either
    # SetForegroundWindow silently failing, or a real person actively using another app
    # (VS Code, a browser) on this same desktop at the same moment. This is checked here
    # AND before every individual click/paste via Assert-TimeDoctorForeground below - a
    # single check at the start of a multi-second sequence is NOT enough, since focus can
    # change again mid-sequence (confirmed: it did, mid-run, during real testing).
    Assert-TimeDoctorForeground -Handle $Handle

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

# Verifies Time Doctor is ACTUALLY the foreground window right now (not just "was
# earlier") and tries to reclaim it once via the AttachThreadInput trick if not. Throws
# rather than proceeding if it still isn't Time Doctor - never click/type blind.
# Call this immediately before EVERY click, scroll, and paste, not just once per script.
function Assert-TimeDoctorForeground {
    param([IntPtr]$Handle)

    $fg = [TDAuto]::GetForegroundWindow()
    if ($fg -eq $Handle) { return }

    Write-Warning "Time Doctor is not the foreground window right now (something else has focus - possibly you, actively using another app). Attempting to reclaim focus..."
    [uint32]$dummyPid = 0
    $fgThread = [TDAuto]::GetWindowThreadProcessId($fg, [ref]$dummyPid)
    $curThread = [TDAuto]::GetCurrentThreadId()
    [TDAuto]::AttachThreadInput($curThread, $fgThread, $true) | Out-Null
    [TDAuto]::SetForegroundWindow($Handle) | Out-Null
    [TDAuto]::BringWindowToTop($Handle) | Out-Null
    [TDAuto]::AttachThreadInput($curThread, $fgThread, $false) | Out-Null
    Start-Sleep -Milliseconds 400

    $fg2 = [TDAuto]::GetForegroundWindow()
    if ($fg2 -ne $Handle) {
        throw "Refusing to act: Time Doctor's window is not in the foreground (currently: $fg2) and could not be reclaimed. Coordinate-based automation is not safe to run blind - re-run once you're not actively using another window, or once any focus-stealing popup/notification has cleared."
    }
}

function Get-TimeDoctorScreenPoint {
    param([hashtable]$Offset, $Rect)
    return @{ X = $Rect.Left + $Offset.X; Y = $Rect.Top + $Offset.Y }
}

# Every click site in the calling scripts should go through this - never call
# [TDAuto]::ClickAt directly - so the foreground check can never accidentally be skipped.
function Invoke-TimeDoctorClick {
    param([IntPtr]$Handle, [hashtable]$Offset, $Rect)
    Assert-TimeDoctorForeground -Handle $Handle
    $point = Get-TimeDoctorScreenPoint -Offset $Offset -Rect $Rect
    [TDAuto]::ClickAt($point.X, $point.Y)
    return $point
}

# Every paste site in the calling scripts should go through this - never call
# SendKeys/Clipboard directly - so we never type into whatever else has focus.
function Invoke-TimeDoctorPaste {
    param([IntPtr]$Handle, [string]$Text)
    Assert-TimeDoctorForeground -Handle $Handle
    [System.Windows.Forms.Clipboard]::SetText($Text)
    Start-Sleep -Milliseconds 200
    # Re-check immediately before the actual keystroke too - pasting is the highest-risk
    # action here (it can land real text in someone else's document), so the gap between
    # the clipboard set and the SendWait keystroke gets its own check.
    Assert-TimeDoctorForeground -Handle $Handle
    [System.Windows.Forms.SendKeys]::SendWait("^v")
}
