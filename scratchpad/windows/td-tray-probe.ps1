<#
  Finds the Time Doctor tray icon (main tray toolbar + overflow window),
  reads its UIA-exposed name/position, right-clicks it, and dumps the
  resulting popup menu's UIA tree (native Windows popup menus are usually
  UIA-accessible regardless of the owning app's own accessibility support).
#>
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class MouseHelper {
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, UIntPtr dwExtraInfo);
    public const uint MOUSEEVENTF_RIGHTDOWN = 0x0008;
    public const uint MOUSEEVENTF_RIGHTUP = 0x0010;
}
"@

function Dump-Element {
    param($el, $depth, $maxDepth)
    if ($null -eq $el) { return $null }
    $name = $el.Current.Name
    $ct = $el.Current.ControlType.ProgrammaticName
    Write-Host ("  " * $depth) "[$ct] '$name'"
    if ($depth -ge $maxDepth) { return }
    $children = $el.FindAll([System.Windows.Automation.TreeScope]::Children, [System.Windows.Automation.Condition]::TrueCondition)
    foreach ($c in $children) {
        Dump-Element -el $c -depth ($depth + 1) -maxDepth $maxDepth
    }
}

$root = [System.Windows.Automation.AutomationElement]::RootElement
$trueCond = [System.Windows.Automation.Condition]::TrueCondition

Write-Host "=== Searching visible tray toolbar (TrayNotifyWnd) ==="
$trayCondition = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ClassNameProperty, "TrayNotifyWnd")
$trayWnd = $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $trayCondition)
if ($trayWnd) {
    Dump-Element -el $trayWnd -depth 0 -maxDepth 6
} else {
    Write-Host "TrayNotifyWnd not found."
}

Write-Host ""
Write-Host "=== Searching hidden/overflow tray icons (NotifyIconOverflowWindow) ==="
Write-Host "Attempting to open the overflow flyout (^ chevron) is not automated here;"
Write-Host "run this manually first if Time Doctor's icon is in the hidden overflow area,"
Write-Host "then re-run this script so NotifyIconOverflowWindow is populated."
$overflowCondition = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ClassNameProperty, "NotifyIconOverflowWindow")
$overflowWnd = $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $overflowCondition)
if ($overflowWnd) {
    Dump-Element -el $overflowWnd -depth 0 -maxDepth 6
} else {
    Write-Host "NotifyIconOverflowWindow not currently present (chevron not opened)."
}

Write-Host ""
Write-Host "=== Looking for a button/element whose name mentions 'Time Doctor' anywhere in the tray tree ==="
$nameCond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, "Time Doctor")
$found = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $nameCond)
Write-Host "Matches found: $($found.Count)"
foreach ($f in $found) {
    $rect = $f.Current.BoundingRectangle
    Write-Host " -> Name='$($f.Current.Name)' ControlType=$($f.Current.ControlType.ProgrammaticName) Rect=$rect"
}
