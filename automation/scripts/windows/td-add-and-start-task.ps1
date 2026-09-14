<#
.SYNOPSIS
  Adds "<ClickUp title>: <ClickUp link>" as a Time Doctor task and starts it.
  Forces the window to a fixed, known size/position first so click coordinates
  are independent of screen resolution/DPI/prior window state. See td-common.ps1
  and TIMEDOCTOR_UIA_FINDINGS.md for why this is coordinate-based, not UIA-based.

.USAGE
  powershell -NoProfile -ExecutionPolicy Bypass -File td-add-and-start-task.ps1 `
      -TaskTitle "Server deployment and Owner side call routing" `
      -TicketLink "https://app.clickup.com/t/3xxxxx" `
      -ProjectName "SENA"
#>
param(
    [Parameter(Mandatory = $true)][string]$TaskTitle,
    [Parameter(Mandatory = $true)][string]$TicketLink,
    # Must match an EXISTING Time Doctor project name exactly (confirmed live: the
    # project field is a constrained dropdown, not free text - typing something that
    # doesn't match a real project silently reverts to whatever was last selected).
    [string]$ProjectName = "",
    # NOTE: default intentionally NOT computed here as "$PSScriptRoot\..." - in Windows
    # PowerShell 5.1, $PSScriptRoot evaluates to an EMPTY STRING while default parameter
    # expressions are evaluated, specifically in any script that also has Mandatory
    # parameters (confirmed via isolated repro). Defaulted below instead, in the script
    # body, where $PSScriptRoot is reliably populated.
    [string]$ScreenshotBeforeOut = "",
    [string]$ScreenshotAfterOut = ""
)

$ErrorActionPreference = "Stop"
if (-not $ScreenshotBeforeOut) { $ScreenshotBeforeOut = "$PSScriptRoot\..\..\data\screenshots\td-before.png" }
if (-not $ScreenshotAfterOut) { $ScreenshotAfterOut = "$PSScriptRoot\..\..\data\screenshots\td-after.png" }
. "$PSScriptRoot\td-common.ps1"

function Write-FailureResult($message) {
    $result = @{ success = $false; error = $message }
    Write-Output "RESULT_JSON: $($result | ConvertTo-Json -Compress)"
}

try {
    New-Item -ItemType Directory -Force -Path (Split-Path $ScreenshotBeforeOut) | Out-Null

    $handle = Find-TimeDoctorDashboardHandle
    if ($handle -eq [IntPtr]::Zero) {
        Write-FailureResult "Time Doctor dashboard window not found (title containing 'Company Time'). Is it open and logged in?"
        exit 1
    }
    Write-Host "Found dashboard window handle: $handle"

    # Throws if Time Doctor can't be confirmed as the actual foreground window - see
    # td-common.ps1. Never click coordinates blind against whatever happens to be on screen.
    $rect = Set-TimeDoctorWindowGeometry -Handle $handle
    Write-Host "Window forced to: L=$($rect.Left) T=$($rect.Top) R=$($rect.Right) B=$($rect.Bottom)"

    $bmp = New-Object System.Drawing.Bitmap $Script:TD_WIN_W, $Script:TD_WIN_H
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($rect.Left, $rect.Top, 0, 0, (New-Object System.Drawing.Size $Script:TD_WIN_W, $Script:TD_WIN_H))
    $bmp.Save($ScreenshotBeforeOut, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()

    $taskText = "$TaskTitle`: $TicketLink"
    Write-Host "Task text: $taskText"

    if ($ProjectName) {
        # Click the project directly in the left sidebar rather than the "Type a
        # Project" autocomplete field - confirmed live that typing there is unreliable
        # (landed on the wrong project even with keyboard-driven selection). Selecting
        # in the sidebar sets it as the active project context for the Add Task row.
        Write-Host "Selecting sidebar project: $ProjectName"
        Select-TimeDoctorSidebarProject -Handle $handle -ProjectName $ProjectName -Rect $rect
    }

    Write-Host "Clicking Add Task field"
    Invoke-TimeDoctorClick -Handle $handle -Offset $Script:TD_ADD_TASK_FIELD -Rect $rect | Out-Null
    Start-Sleep -Milliseconds 400

    Invoke-TimeDoctorPaste -Handle $handle -Text $taskText
    Start-Sleep -Milliseconds 400

    Write-Host "Clicking Add+Start button"
    Invoke-TimeDoctorClick -Handle $handle -Offset $Script:TD_ADD_START_BUTTON -Rect $rect | Out-Null
    Start-Sleep -Milliseconds 800

    # Check (don't reclaim - the click already happened, reclaiming now would be
    # pointless) whether focus was still on Time Doctor for the final click, so the
    # result can flag it honestly if not - a screenshot taken while focus was
    # elsewhere doesn't prove the click landed where intended.
    $focusHeldThroughout = ([TDAuto]::GetForegroundWindow() -eq $handle)

    $bmp2 = New-Object System.Drawing.Bitmap $Script:TD_WIN_W, $Script:TD_WIN_H
    $g2 = [System.Drawing.Graphics]::FromImage($bmp2)
    $g2.CopyFromScreen($rect.Left, $rect.Top, 0, 0, (New-Object System.Drawing.Size $Script:TD_WIN_W, $Script:TD_WIN_H))
    $bmp2.Save($ScreenshotAfterOut, [System.Drawing.Imaging.ImageFormat]::Png)
    $g2.Dispose(); $bmp2.Dispose()

    $result = @{
        success = $true
        taskText = $taskText
        projectName = $ProjectName
        screenshotBefore = $ScreenshotBeforeOut
        screenshotAfter = $ScreenshotAfterOut
        focusHeldThroughout = $focusHeldThroughout
    }
    Write-Output "RESULT_JSON: $($result | ConvertTo-Json -Compress)"
} catch {
    Write-FailureResult $_.Exception.Message
    exit 1
}
