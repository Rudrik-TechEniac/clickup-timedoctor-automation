param(
    [long]$Handle,
    [string]$OutFile
)

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinShot {
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    public struct RECT { public int Left, Top, Right, Bottom; }
}
"@
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

[WinShot]::SetProcessDPIAware() | Out-Null

$h = [IntPtr]$Handle
[WinShot]::ShowWindowAsync($h, 9) | Out-Null   # SW_RESTORE
Start-Sleep -Milliseconds 300
[WinShot]::SetForegroundWindow($h) | Out-Null
Start-Sleep -Milliseconds 500

$rect = New-Object WinShot+RECT
[WinShot]::GetWindowRect($h, [ref]$rect) | Out-Null
$width = $rect.Right - $rect.Left
$height = $rect.Bottom - $rect.Top
Write-Host "Window rect: L=$($rect.Left) T=$($rect.Top) W=$width H=$height"

$bmp = New-Object System.Drawing.Bitmap $width, $height
$graphics = [System.Drawing.Graphics]::FromImage($bmp)
$graphics.CopyFromScreen($rect.Left, $rect.Top, 0, 0, (New-Object System.Drawing.Size $width, $height))
$bmp.Save($OutFile, [System.Drawing.Imaging.ImageFormat]::Png)
$graphics.Dispose()
$bmp.Dispose()
Write-Host "Saved screenshot to $OutFile"

# Also echo the rect as JSON for downstream coordinate math
[PSCustomObject]@{ Left = $rect.Left; Top = $rect.Top; Right = $rect.Right; Bottom = $rect.Bottom; Width = $width; Height = $height } |
    ConvertTo-Json | Out-File "$OutFile.rect.json" -Encoding utf8
