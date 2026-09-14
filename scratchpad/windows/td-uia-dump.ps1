<#
.SYNOPSIS
  Dumps the UI Automation tree of the running Time Doctor desktop app window(s)
  to find accessible controls (looking for a Start/Stop/Pause tracking control).

.USAGE
  powershell -NoProfile -ExecutionPolicy Bypass -File td-uia-dump.ps1 -OutFile out.json
#>

param(
    [string]$ProcessNamePattern = "Time Doctor",
    [string]$OutFile = "$PSScriptRoot\td-uia-dump.json",
    [int]$MaxDepth = 12
)

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

function Get-ElementInfo {
    param([System.Windows.Automation.AutomationElement]$Element)

    $patterns = @()
    foreach ($patternInfo in [System.Windows.Automation.AutomationPattern]::All) {}
    # Check common patterns explicitly (enumerating .All is unreliable across .NET versions)
    $checks = @(
        @{ Name = "Invoke"; Pattern = [System.Windows.Automation.InvokePattern]::Pattern },
        @{ Name = "Toggle"; Pattern = [System.Windows.Automation.TogglePattern]::Pattern },
        @{ Name = "SelectionItem"; Pattern = [System.Windows.Automation.SelectionItemPattern]::Pattern },
        @{ Name = "ExpandCollapse"; Pattern = [System.Windows.Automation.ExpandCollapsePattern]::Pattern }
    )
    foreach ($c in $checks) {
        $obj = $null
        if ($Element.TryGetCurrentPattern($c.Pattern, [ref]$obj)) {
            $patterns += $c.Name
        }
    }

    [PSCustomObject]@{
        Name          = $Element.Current.Name
        ControlType   = $Element.Current.ControlType.ProgrammaticName
        AutomationId  = $Element.Current.AutomationId
        ClassName     = $Element.Current.ClassName
        IsEnabled     = $Element.Current.IsEnabled
        IsOffscreen   = $Element.Current.IsOffscreen
        BoundingBox   = $Element.Current.BoundingRectangle.ToString()
        Patterns      = $patterns
    }
}

function Walk-Tree {
    param(
        [System.Windows.Automation.AutomationElement]$Element,
        [int]$Depth,
        [int]$MaxDepth
    )

    $info = Get-ElementInfo -Element $Element
    $info | Add-Member -NotePropertyName Depth -NotePropertyValue $Depth
    $node = [ordered]@{
        Info     = $info
        Children = @()
    }

    if ($Depth -ge $MaxDepth) { return $node }

    $condition = [System.Windows.Automation.Condition]::TrueCondition
    $children = $Element.FindAll([System.Windows.Automation.TreeScope]::Children, $condition)
    foreach ($child in $children) {
        $node.Children += (Walk-Tree -Element $child -Depth ($Depth + 1) -MaxDepth $MaxDepth)
    }
    return $node
}

Write-Host "Looking for processes matching '$ProcessNamePattern'..."
$procs = Get-Process | Where-Object { $_.ProcessName -match [regex]::Escape($ProcessNamePattern) -and $_.MainWindowHandle -ne 0 }

if (-not $procs) {
    Write-Warning "No process with a main window found matching '$ProcessNamePattern'. Listing all matching processes (no window):"
    Get-Process | Where-Object { $_.ProcessName -match [regex]::Escape($ProcessNamePattern) } | Format-Table ProcessName, Id, MainWindowHandle
    Write-Warning "Trying Desktop root scan for top-level windows with a matching title instead..."
}

$results = @()

foreach ($proc in $procs) {
    Write-Host "Dumping tree for PID $($proc.Id), window: '$($proc.MainWindowTitle)'"
    try {
        $root = [System.Windows.Automation.AutomationElement]::FromHandle($proc.MainWindowHandle)
        $tree = Walk-Tree -Element $root -Depth 0 -MaxDepth $MaxDepth
        $results += [ordered]@{
            ProcessId    = $proc.Id
            WindowTitle  = $proc.MainWindowTitle
            Tree         = $tree
        }
    } catch {
        Write-Warning "Failed to dump PID $($proc.Id): $_"
    }
}

# Also scan all top-level desktop windows for anything with "Time Doctor" in the title,
# in case the tracked window isn't the one Get-Process reports as MainWindowHandle.
Write-Host "Scanning all top-level windows for title match..."
$desktop = [System.Windows.Automation.AutomationElement]::RootElement
$condition = [System.Windows.Automation.Condition]::TrueCondition
$topWindows = $desktop.FindAll([System.Windows.Automation.TreeScope]::Children, $condition)
foreach ($w in $topWindows) {
    try {
        if ($w.Current.Name -match "Time Doctor") {
            $already = $results | Where-Object { $_.WindowTitle -eq $w.Current.Name }
            if (-not $already) {
                Write-Host "Found top-level window: '$($w.Current.Name)'"
                $tree = Walk-Tree -Element $w -Depth 0 -MaxDepth $MaxDepth
                $results += [ordered]@{
                    ProcessId    = $null
                    WindowTitle  = $w.Current.Name
                    Tree         = $tree
                }
            }
        }
    } catch {}
}

if (-not $results) {
    Write-Warning "No Time Doctor windows found at all (main window or top-level scan). Is the app minimized to tray only? Try restoring its window first."
}

$results | ConvertTo-Json -Depth 40 | Out-File -FilePath $OutFile -Encoding utf8
Write-Host "Wrote dump to $OutFile"
