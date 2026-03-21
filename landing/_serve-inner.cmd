@echo OFF
cd /d "%~dp0"
title LMS-local-5500
chcp 65001 >nul 2>&1

set "PORT=5500"
set "LOG=%~dp0run-local-last.log"

>>"%LOG%" echo [%date% %time%] serve-inner started

echo.
echo  LMS local server  PORT=%PORT%
echo  Open: http://localhost:%PORT%/app.html
echo  Stop: Ctrl+C
echo.

timeout /t 1 /nobreak >nul 2>nul
start "" "http://localhost:%PORT%/app.html"

where python >nul 2>&1
if not errorlevel 1 (
  echo Using: Python
  >>"%LOG%" echo using python
  python -m http.server %PORT%
  >>"%LOG%" echo python finished
  goto :end
)

where node >nul 2>&1
if not errorlevel 1 (
  echo Using: Node npx http-server
  >>"%LOG%" echo using node
  call npx --yes http-server -p %PORT% -c-1 .
  >>"%LOG%" echo node exit
  goto :end
)

echo.
echo  ERROR: No "python" and no "node" in PATH.
echo  Install Python 3 or Node.js, enable "Add to PATH", reopen terminal.
echo.
>>"%LOG%" echo no python no node
pause

:end
echo.
echo Server stopped.
pause
