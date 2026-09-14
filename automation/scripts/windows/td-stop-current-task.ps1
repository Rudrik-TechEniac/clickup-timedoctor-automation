<#
  Stops the currently running Time Doctor task by clicking the banner's Stop button.
  Same fixed-geometry approach as td-add-and-start-task.ps1 - see td-common.ps1.
#>
param(
    # See td-add-and-start-task.ps1 for why this isn't defaulted here directly -
    # $PSScriptRoot is unreliable inside param() default expressions in a script
    # with Mandatory parameters. Harmless here (no mandatory params) but kept
    # consistent/defensive in case one is added later.
    [string]$ScreenshotAfterOut = ""
)

$ErrorActionPreference = "Stop"
if (-not $ScreenshotAfterOut) { $ScreenshotAfterOut = "$PSScriptRoot\..\..\data\screenshots\td-after-stop.png" }
. "$PSScriptRoot\td-common.ps1"

function Write-FailureResult($message) {
    $result = @{ success = $false; error = $message }
    Write-Output "RESULT_JSON: $($result | ConvertTo-Json -Compress)"
}

try {
    New-Item -ItemType Directory -Force -Path (Split-Path $ScreenshotAfterOut) | Out-Null

    $handle = Find-TimeDoctorDashboardHandle
    if ($handle -eq [IntPtr]::Zero) {
        Write-FailureResult "Time Doctor dashboard window not found."
        exit 1
    }

    # Throws if Time Doctor can't be confirmed as the actual foreground window - see
    # td-common.ps1. Never click coordinates blind against whatever happens to be on screen.
    $rect = Set-TimeDoctorWindowGeometry -Handle $handle

    Write-Host "Clicking Stop button"
    Invoke-TimeDoctorClick -Handle $handle -Offset $Script:TD_STOP_BUTTON -Rect $rect | Out-Null
    Start-Sleep -Milliseconds 800

    $focusHeldThroughout = ([TDAuto]::GetForegroundWindow() -eq $handle)

    $bmp = New-Object System.Drawing.Bitmap $Script:TD_WIN_W, $Script:TD_WIN_H
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($rect.Left, $rect.Top, 0, 0, (New-Object System.Drawing.Size $Script:TD_WIN_W, $Script:TD_WIN_H))
    $bmp.Save($ScreenshotAfterOut, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()

    $result = @{ success = $true; screenshotAfter = $ScreenshotAfterOut; focusHeldThroughout = $focusHeldThroughout }
    Write-Output "RESULT_JSON: $($result | ConvertTo-Json -Compress)"
} catch {
    Write-FailureResult $_.Exception.Message
    exit 1
}
