@echo OFF
setlocal
set "ROOT=%~dp0"
set "LOG=%ROOT%landing\run-local-last.log"

>>"%LOG%" echo.
>>"%LOG%" echo ===== [%date% %TIME%] run-local.bat =====

cd /d "%ROOT%" 2>>"%LOG%"
if errorlevel 1 (
  echo FAILED: cannot cd to script folder
  echo Log: %LOG%
  >>"%LOG%" echo cd root failed
  pause
  exit /b 1
)

if not exist "%ROOT%landing\index.html" (
  echo ERROR: landing\index.html not found
  echo Put run-local.bat in project ROOT ^(folder that contains "landing"^).
  echo Current: %CD%
  echo Log: %LOG%
  >>"%LOG%" echo missing index.html
  pause
  exit /b 1
)

if not exist "%ROOT%landing\_serve-inner.cmd" (
  echo ERROR: landing\_serve-inner.cmd not found
  >>"%LOG%" echo missing serve-inner
  pause
  exit /b 1
)

echo.
echo  Starting server in NEW window ^(title: LMS-local-5500^)
echo  Check Taskbar / second screen if you do not see it.
echo  Log: %LOG%
echo.

rem Trailing backslash in %ROOT% before quote breaks cd; use %~dp0landing without extra quote issue
start "LMS-local-5500" cmd /k cd /d "%~dp0landing" ^& call _serve-inner.cmd

>>"%LOG%" echo start issued

echo  You may close THIS window. Server runs in the other one.
echo.
pause
endlocal
