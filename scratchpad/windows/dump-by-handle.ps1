param(
    [long]$Handle,
    [string]$OutFile,
    [int]$MaxDepth = 25
)

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

function Get-ElementInfo {
    param([System.Windows.Automation.AutomationElement]$Element)
    $checks = @(
        @{ Name = "Invoke"; Pattern = [System.Windows.Automation.InvokePattern]::Pattern },
        @{ Name = "Toggle"; Pattern = [System.Windows.Automation.TogglePattern]::Pattern },
        @{ Name = "SelectionItem"; Pattern = [System.Windows.Automation.SelectionItemPattern]::Pattern },
        @{ Name = "ExpandCollapse"; Pattern = [System.Windows.Automation.ExpandCollapsePattern]::Pattern }
    )
    $patterns = @()
    foreach ($c in $checks) {
        $obj = $null
        if ($Element.TryGetCurrentPattern($c.Pattern, [ref]$obj)) { $patterns += $c.Name }
    }
    [PSCustomObject]@{
        Name          = $Element.Current.Name
        ControlType   = $Element.Current.ControlType.ProgrammaticName
        AutomationId  = $Element.Current.AutomationId
        ClassName     = $Element.Current.ClassName
        IsEnabled     = $Element.Current.IsEnabled
        BoundingBox   = $Element.Current.BoundingRectangle.ToString()
        Patterns      = $patterns
    }
}

function Walk-Tree {
    param([System.Windows.Automation.AutomationElement]$Element, [int]$Depth, [int]$MaxDepth)
    $info = Get-ElementInfo -Element $Element
    $info | Add-Member -NotePropertyName Depth -NotePropertyValue $Depth
    $node = [ordered]@{ Info = $info; Children = @() }
    if ($Depth -ge $MaxDepth) { return $node }
    $children = $Element.FindAll([System.Windows.Automation.TreeScope]::Children, [System.Windows.Automation.Condition]::TrueCondition)
    foreach ($child in $children) {
        $node.Children += (Walk-Tree -Element $child -Depth ($Depth + 1) -MaxDepth $MaxDepth)
    }
    return $node
}

$el = [System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]$Handle)
$tree = Walk-Tree -Element $el -Depth 0 -MaxDepth $MaxDepth
$tree | ConvertTo-Json -Depth 60 | Out-File -FilePath $OutFile -Encoding utf8
Write-Host "Wrote $OutFile"
