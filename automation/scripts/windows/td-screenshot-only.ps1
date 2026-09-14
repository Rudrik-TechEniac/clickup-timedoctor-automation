<#
  Pure screenshot utility - NO clicking, ever. Forces window geometry (safe: just
  resize/foreground, not a click into app content) and captures the result. Use this
  any time you just need to see the current state of the Time Doctor window.
#>
param([string]$OutFile = "")
$ErrorActionPreference = "Stop"
if (-not $OutFile) { $OutFile = "$PSScriptRoot\..\..\data\screenshots\td-screenshot.png" }
. "$PSScriptRoot\td-common.ps1"

$handle = Find-TimeDoctorDashboardHandle
if ($handle -eq [IntPtr]::Zero) { Write-Error "Time Doctor window not found."; exit 1 }
$rect = Set-TimeDoctorWindowGeometry -Handle $handle

$bmp = New-Object System.Drawing.Bitmap $Script:TD_WIN_W, $Script:TD_WIN_H
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($rect.Left, $rect.Top, 0, 0, (New-Object System.Drawing.Size $Script:TD_WIN_W, $Script:TD_WIN_H))
$bmp.Save($OutFile, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
Write-Host "Screenshot: $OutFile"
