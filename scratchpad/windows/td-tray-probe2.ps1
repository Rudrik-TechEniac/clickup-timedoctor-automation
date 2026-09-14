Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

function Dump-Element {
    param($el, $depth, $maxDepth)
    if ($null -eq $el) { return }
    $name = $el.Current.Name
    $ct = $el.Current.ControlType.ProgrammaticName
    $aid = $el.Current.AutomationId
    Write-Host ("  " * $depth) "[$ct] Name='$name' AutomationId='$aid'"
    if ($depth -ge $maxDepth) { return }
    $children = $el.FindAll([System.Windows.Automation.TreeScope]::Children, [System.Windows.Automation.Condition]::TrueCondition)
    foreach ($c in $children) {
        Dump-Element -el $c -depth ($depth + 1) -maxDepth $maxDepth
    }
}

$root = [System.Windows.Automation.AutomationElement]::RootElement

Write-Host "=== Looking for 'Show hidden icons' chevron button ==="
$chevronCond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, "Show hidden icons")
$chevron = $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $chevronCond)
if ($chevron) {
    Write-Host "Found chevron, invoking..."
    $invokePattern = $null
    if ($chevron.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$invokePattern)) {
        $invokePattern.Invoke()
        Start-Sleep -Milliseconds 800
    } else {
        Write-Host "No InvokePattern on chevron."
    }
} else {
    Write-Host "Chevron 'Show hidden icons' not found by exact name; searching for any Button whose name contains 'hidden'..."
    $allButtons = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Button)))
    foreach ($b in $allButtons) {
        if ($b.Current.Name -match "hidden") {
            Write-Host "Match: $($b.Current.Name)"
            $invokePattern = $null
            if ($b.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$invokePattern)) {
                $invokePattern.Invoke()
                Start-Sleep -Milliseconds 800
            }
        }
    }
}

Write-Host ""
Write-Host "=== Re-checking NotifyIconOverflowWindow after chevron click ==="
$overflowCondition = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ClassNameProperty, "NotifyIconOverflowWindow")
$overflowWnd = $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $overflowCondition)
if ($overflowWnd) {
    Dump-Element -el $overflowWnd -depth 0 -maxDepth 8
} else {
    Write-Host "Still not present."
}

Write-Host ""
Write-Host "=== Broad search: any element anywhere with Name containing 'Time Doctor' ==="
$nameCond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, "Time Doctor")
$found = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $nameCond)
Write-Host "Matches: $($found.Count)"
foreach ($f in $found) {
    Write-Host " -> [$($f.Current.ControlType.ProgrammaticName)] '$($f.Current.Name)' AutomationId='$($f.Current.AutomationId)' Rect=$($f.Current.BoundingRectangle)"
}
