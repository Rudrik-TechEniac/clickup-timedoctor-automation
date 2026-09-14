<#
.SYNOPSIS
  Adds "<ClickUp title>: <ClickUp link>" as a Time Doctor task and starts it.
  Forces the window to a fixed, known size/position first so click coordinates
  are independent of screen resolution/DPI/prior window state. See td-common.ps1
  and TIMEDOCTOR_UIA_FINDINGS.md for why this is coordinate-based, not UIA-based.

.USAGE
  powershell -NoProfile -ExecutionPolicy Bypass -File td-add-and-start-task.ps1 `
      -TaskTitle "Server deployment and Owner side call routing" `
      -TicketLink "https://app.clickup.com/t/3xxxxx"
#>
param(
    [Parameter(Mandatory = $true)][string]$TaskTitle,
    [Parameter(Mandatory = $true)][string]$TicketLink,
    [string]$ScreenshotBeforeOut = "C:\Users\teche\OneDrive\Desktop\ClickUp\scratchpad\windows\td-before.png",
    [string]$ScreenshotAfterOut = "C:\Users\teche\OneDrive\Desktop\ClickUp\scratchpad\windows\td-after.png"
)

. "$PSScriptRoot\td-common.ps1"

$handle = Find-TimeDoctorDashboardHandle
if ($handle -eq [IntPtr]::Zero) {
    Write-Error "Could not find Time Doctor dashboard window (title containing 'Company Time'). Is it open and logged in?"
    exit 1
}
Write-Host "Found dashboard window handle: $handle"

$rect = Set-TimeDoctorWindowGeometry -Handle $handle
Write-Host "Window forced to: L=$($rect.Left) T=$($rect.Top) R=$($rect.Right) B=$($rect.Bottom)"

$bmp = New-Object System.Drawing.Bitmap $Script:TD_WIN_W, $Script:TD_WIN_H
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($rect.Left, $rect.Top, 0, 0, (New-Object System.Drawing.Size $Script:TD_WIN_W, $Script:TD_WIN_H))
$bmp.Save($ScreenshotBeforeOut, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()

$taskText = "$TaskTitle`: $TicketLink"
Write-Host "Task text: $taskText"

$p1 = Get-TimeDoctorScreenPoint -Offset $Script:TD_ADD_TASK_FIELD -Rect $rect
Write-Host "Clicking Add Task field at ($($p1.X), $($p1.Y))"
[TDAuto]::ClickAt($p1.X, $p1.Y)
Start-Sleep -Milliseconds 400

[System.Windows.Forms.Clipboard]::SetText($taskText)
Start-Sleep -Milliseconds 200
[System.Windows.Forms.SendKeys]::SendWait("^v")
Start-Sleep -Milliseconds 400

$p2 = Get-TimeDoctorScreenPoint -Offset $Script:TD_ADD_START_BUTTON -Rect $rect
Write-Host "Clicking Add+Start button at ($($p2.X), $($p2.Y))"
[TDAuto]::ClickAt($p2.X, $p2.Y)
Start-Sleep -Milliseconds 800

$bmp2 = New-Object System.Drawing.Bitmap $Script:TD_WIN_W, $Script:TD_WIN_H
$g2 = [System.Drawing.Graphics]::FromImage($bmp2)
$g2.CopyFromScreen($rect.Left, $rect.Top, 0, 0, (New-Object System.Drawing.Size $Script:TD_WIN_W, $Script:TD_WIN_H))
$bmp2.Save($ScreenshotAfterOut, [System.Drawing.Imaging.ImageFormat]::Png)
$g2.Dispose(); $bmp2.Dispose()

Write-Host "Done. Compare $ScreenshotBeforeOut and $ScreenshotAfterOut to verify."
