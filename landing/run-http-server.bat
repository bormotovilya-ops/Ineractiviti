@echo off
setlocal
chcp 65001 >nul
cd /d "%~dp0"

set "PORT=5500"
title LMS port %PORT%

echo http://localhost:%PORT%/app.html
echo Ctrl+C - стоп.
echo.

where python >nul 2>&1
if not errorlevel 1 (
  python -m http.server %PORT%
  goto :eof
)

where node >nul 2>&1
if not errorlevel 1 (
  call npx --yes http-server -p %PORT% -c-1 .
  goto :eof
)

echo Нужны Python или Node.js в PATH.
pause
