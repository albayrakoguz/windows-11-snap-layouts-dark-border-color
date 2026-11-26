@echo off
rem Windows 11 Snap Layouts Dark Border Color - single-file installer.
rem Everything below the marker line at the end of this header is a plain PowerShell script you can read.
rem Uninstall:  Windows11-DarkBorderColor-Setup.cmd -Uninstall   (or Settings > Apps)
setlocal
set "DBC_T=%TEMP%\dbc-setup-%RANDOM%.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$m='#'+'<PS>'; $t=[IO.File]::ReadAllText('%~f0'); $i=$t.IndexOf($m); if($i -lt 0){exit 1}; [IO.File]::WriteAllText('%DBC_T%',$t.Substring($i),[Text.Encoding]::UTF8)"
if not exist "%DBC_T%" (echo Could not unpack the installer. & pause & exit /b 1)
powershell -NoProfile -ExecutionPolicy Bypass -File "%DBC_T%" %*
del "%DBC_T%" >nul 2>&1
echo.
pause
exit /b
