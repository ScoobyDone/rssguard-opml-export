@echo off
setlocal
rem Edit these paths. The output directory must already exist.
set "PYTHON=C:\Python313\python.exe"
set "SCRIPT=C:\Scripts\rssguard-opml.py"
set "DATABASE=C:\RSSGuard\data\database.db"
set "OUTDIR=C:\Backups\RSSGuard"
rem Local wall-clock time, independent of Windows regional date settings.
set "STAMP="
for /f "delims=" %%I in ('powershell.exe -NoProfile -Command "Get-Date -Format yyyy-MM-dd_HH-mm-ss"') do set "STAMP=%%I"
if not defined STAMP exit /b 1
set "TARGET=%OUTDIR%\subscriptions_%STAMP%.opml"
rem GetTempFileName creates a unique file, avoiding concurrent temporary-file clashes.
set "TEMPFILE="
for /f "delims=" %%I in ('powershell.exe -NoProfile -Command "[IO.Path]::GetTempFileName()"') do set "TEMPFILE=%%I"
if not defined TEMPFILE exit /b 1
"%PYTHON%" "%SCRIPT%" "%DATABASE%" > "%TEMPFILE%" 2>> "%OUTDIR%\export-errors.log"
if errorlevel 1 goto failed
rem Two-argument File.Move refuses to overwrite, including same-second collisions.
powershell.exe -NoProfile -Command "$ErrorActionPreference='Stop'; try { [IO.File]::Move($env:TEMPFILE,$env:TARGET) } catch { [Console]::Error.WriteLine($_.Exception.Message); exit 1 }" 2>> "%OUTDIR%\export-errors.log"
if errorlevel 1 goto failed
exit /b 0
:failed
if exist "%TEMPFILE%" del /q "%TEMPFILE%"
exit /b 1
