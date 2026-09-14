<#
  Stops the currently running Time Doctor task by clicking the banner's Stop button.
  Same fixed-geometry approach as td-add-and-start-task.ps1 - see td-common.ps1.
#>
param(
    [string]$ScreenshotAfterOut = "C:\Users\teche\OneDrive\Desktop\ClickUp\scratchpad\windows\td-after-stop.png"
)

. "$PSScriptRoot\td-common.ps1"

$handle = Find-TimeDoctorDashboardHandle
if ($handle -eq [IntPtr]::Zero) {
    Write-Error "Could not find Time Doctor dashboard window."
    exit 1
}

$rect = Set-TimeDoctorWindowGeometry -Handle $handle

$p = Get-TimeDoctorScreenPoint -Offset $Script:TD_STOP_BUTTON -Rect $rect
Write-Host "Clicking Stop button at ($($p.X), $($p.Y))"
[TDAuto]::ClickAt($p.X, $p.Y)
Start-Sleep -Milliseconds 800

$bmp = New-Object System.Drawing.Bitmap $Script:TD_WIN_W, $Script:TD_WIN_H
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($rect.Left, $rect.Top, 0, 0, (New-Object System.Drawing.Size $Script:TD_WIN_W, $Script:TD_WIN_H))
$bmp.Save($ScreenshotAfterOut, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
Write-Host "Done. Screenshot: $ScreenshotAfterOut"
