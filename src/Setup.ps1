# Windows 11 Snap Layouts Dark Border Color - installer / uninstaller
#
# Install  : double-click Windows11-DarkBorderColor-Setup.cmd   (or: .\Setup.ps1 -Color 222222)
# Uninstall: Settings > Apps > "Windows 11 Snap Layouts Dark Border Color"   (or: .\Setup.ps1 -Uninstall)
#
# Paints the border of every window with the color you choose (DWMWA_BORDER_COLOR, Windows 11 build 22000+).
# A tiny hidden script re-applies the color once per second so new windows are covered too;
# it starts at sign-in through a shortcut in your Startup folder.
param(
    [string]$Color,                 # RRGGBB, e.g. 1a1a1a (default). If omitted, you are asked.
    [switch]$Uninstall,
    [string]$InstallDir,
    [switch]$NoRegister,            # testing: write files only (no startup shortcut, no registry, no process changes)
    [switch]$NoLaunch
)
$ErrorActionPreference = 'Stop'

$AppName   = 'Windows 11 Snap Layouts Dark Border Color'
$UninstKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Win11DarkBorderColor'
if (-not $InstallDir) { $InstallDir = Join-Path $env:LOCALAPPDATA 'Programs\Win11DarkBorderColor' }
$StartupLnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'Win11DarkBorderColor.lnk'

# ---------------------------------------------------------------- embedded files
$BorderPs1 = @'
param([switch]$Reset)
$ErrorActionPreference = 'SilentlyContinue'

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class W {
  delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc p, IntPtr l);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr h, int attr, ref int v, int size);
  public static void Apply(int color) {
    EnumWindows((h, l) => {
      if (!IsWindowVisible(h)) return true;
      int c = color;
      DwmSetWindowAttribute(h, 34, ref c, 4);   // DWMWA_BORDER_COLOR
      return true;
    }, IntPtr.Zero);
  }
}
"@

# on uninstall: give every window its default border back (DWMWA_COLOR_DEFAULT = 0xFFFFFFFF)
if ($Reset) { [W]::Apply(-1); exit }

$created = $false
$mutex = New-Object System.Threading.Mutex($true, 'Local\Win11DarkBorderColor', [ref]$created)
if (-not $created) { exit }   # already running

# color: color.txt (RRGGBB), falls back to 1a1a1a
$hex = '1a1a1a'
try {
    $t = (Get-Content (Join-Path $PSScriptRoot 'color.txt') -ErrorAction Stop | Select-Object -First 1).Trim().TrimStart('#')
    if ($t -match '^[0-9a-fA-F]{6}$') { $hex = $t }
} catch {}
$r = [Convert]::ToInt32($hex.Substring(0, 2), 16)
$g = [Convert]::ToInt32($hex.Substring(2, 2), 16)
$b = [Convert]::ToInt32($hex.Substring(4, 2), 16)
$color = ($b -shl 16) -bor ($g -shl 8) -bor $r      # COLORREF = 0x00BBGGRR

while ($true) {
    try { [W]::Apply($color) } catch {}
    Start-Sleep -Milliseconds 1000
}
'@

# the startup shortcut runs this, so no console window ever appears
$LauncherVbs = @'
Set fso = CreateObject("Scripting.FileSystemObject")
d = fso.GetParentFolderName(WScript.ScriptFullName)
CreateObject("WScript.Shell").Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & d & "\darkborder.ps1""", 0, False
'@

# ---------------------------------------------------------------- helpers
function Stop-DarkBorder {
    # only PowerShell processes running darkborder.ps1 / border.ps1 (this installer's name does not match)
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
        Where-Object { $_.CommandLine -match 'border\.ps1' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}

function Remove-LegacyAutostart {
    # clean up a manual "Run key" setup so the tool is not started twice
    foreach ($name in 'WindowBorderDark', 'Win11DarkBorderColor') {
        try { Remove-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name $name -ErrorAction SilentlyContinue } catch {}
        try { Remove-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run' -Name $name -ErrorAction SilentlyContinue } catch {}
    }
    $old = Join-Path ([Environment]::GetFolderPath('Startup')) 'WindowBorderDark.lnk'
    if (Test-Path $old) { Remove-Item $old -Force -ErrorAction SilentlyContinue }
}

# ---------------------------------------------------------------- uninstall
if ($Uninstall) {
    Write-Host "Removing $AppName ..."
    if (-not $NoRegister) {
        Stop-DarkBorder
        $border = Join-Path $InstallDir 'darkborder.ps1'
        if (Test-Path $border) {
            Start-Process powershell.exe -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$border`"", '-Reset' -Wait -WindowStyle Hidden
        }
        if (Test-Path $StartupLnk) { Remove-Item $StartupLnk -Force }
        Remove-LegacyAutostart
        if (Test-Path $UninstKey) { Remove-Item $UninstKey -Recurse -Force }
    }
    if (Test-Path $InstallDir) {
        # this script may be running from the install folder: delete it after the process exits
        Start-Process cmd.exe -ArgumentList "/c ping 127.0.0.1 -n 3 > nul & rmdir /s /q `"$InstallDir`"" -WindowStyle Hidden
    }
    Write-Host 'Removed. Window borders are back to the Windows default.'
    return
}

# ---------------------------------------------------------------- install
if ([Environment]::OSVersion.Version.Build -lt 22000) {
    throw 'This tool needs Windows 11 (build 22000 or newer). Windows 10 has no window border color API.'
}

if (-not $Color) {
    if ([Environment]::UserInteractive -and -not $NoLaunch) {
        $in = Read-Host 'Border color as RRGGBB (press Enter for 1a1a1a dark gray; 000000 = black)'
        $Color = if ([string]::IsNullOrWhiteSpace($in)) { '1a1a1a' } else { $in }
    } else { $Color = '1a1a1a' }
}
$Color = $Color.Trim().TrimStart('#')
if ($Color -notmatch '^[0-9a-fA-F]{6}$') { throw "Invalid color '$Color'. Use 6 hex digits, for example 1a1a1a." }

Write-Host "Installing $AppName -> $InstallDir"
if (-not $NoRegister) { Stop-DarkBorder }

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
Set-Content -Path (Join-Path $InstallDir 'darkborder.ps1')  -Value $BorderPs1   -Encoding UTF8
Set-Content -Path (Join-Path $InstallDir 'run-hidden.vbs')  -Value $LauncherVbs -Encoding ASCII
Set-Content -Path (Join-Path $InstallDir 'color.txt')       -Value $Color       -Encoding ASCII
Copy-Item -Path $PSCommandPath -Destination (Join-Path $InstallDir 'Setup.ps1') -Force -ErrorAction SilentlyContinue

if (-not $NoRegister) {
    # start at sign-in: Startup-folder shortcut (visible in Task Manager > Startup apps)
    $sh = New-Object -ComObject WScript.Shell
    $lnk = $sh.CreateShortcut($StartupLnk)
    $lnk.TargetPath = Join-Path $env:SystemRoot 'System32\wscript.exe'
    $lnk.Arguments = "`"$(Join-Path $InstallDir 'run-hidden.vbs')`""
    $lnk.WorkingDirectory = $InstallDir
    $lnk.WindowStyle = 7
    $lnk.Description = $AppName
    $lnk.Save()
    Remove-LegacyAutostart

    # Settings > Apps > Installed apps entry
    New-Item -Path $UninstKey -Force | Out-Null
    $setup = Join-Path $InstallDir 'Setup.ps1'
    $props = @{
        DisplayName          = $AppName
        DisplayVersion       = '1.0.0'
        InstallLocation      = $InstallDir
        UninstallString      = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$setup`" -Uninstall"
        QuietUninstallString = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$setup`" -Uninstall"
    }
    foreach ($k in $props.Keys) { Set-ItemProperty -Path $UninstKey -Name $k -Value $props[$k] }
    Set-ItemProperty -Path $UninstKey -Name 'NoModify' -Value 1 -Type DWord
    Set-ItemProperty -Path $UninstKey -Name 'NoRepair' -Value 1 -Type DWord

    if (-not $NoLaunch) {
        Start-Process wscript.exe -ArgumentList "`"$(Join-Path $InstallDir 'run-hidden.vbs')`""
        Start-Sleep -Seconds 2
    }
}
Write-Host "Done. Border color: #$Color  (it starts by itself when you sign in)"
