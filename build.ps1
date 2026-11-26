# Builds the single-file installer:  .\build.ps1
# Output: release\Windows11-DarkBorderColor-Setup.cmd  (attach this file to a GitHub Release)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$head = [IO.File]::ReadAllText("$root\src\header.cmd").TrimEnd()
$body = [IO.File]::ReadAllText("$root\src\Setup.ps1")
New-Item -ItemType Directory -Force -Path "$root\release" | Out-Null
$out = "$root\release\Windows11-DarkBorderColor-Setup.cmd"
[IO.File]::WriteAllText($out, $head + "`r`n#<PS>`r`n" + $body, (New-Object System.Text.UTF8Encoding($false)))
Write-Host ("Built: {0}  ({1:N1} KB)" -f $out, ((Get-Item $out).Length / 1KB))
