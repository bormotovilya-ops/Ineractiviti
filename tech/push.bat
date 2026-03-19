@echo off
setlocal enabledelayedexpansion

REM Usage:
REM   push.bat "commit message"
REM If message not provided, will prompt.

cd /d "%~dp0"

echo.
echo === Git status ===
git status
if errorlevel 1 (
  echo.
  echo [ERROR] Git not available or repo not initialized.
  exit /b 1
)

set "MSG=%~1"
if "%MSG%"=="" (
  echo.
  set /p MSG=Commit message: 
)

if "%MSG%"=="" (
  echo.
  echo [ERROR] Empty commit message. Aborting.
  exit /b 1
)

echo.
echo === Staging changes ===
git add -A
if errorlevel 1 (
  echo.
  echo [ERROR] Failed to stage changes.
  exit /b 1
)

echo.
echo === Committing ===
git diff --cached --quiet
if not errorlevel 1 (
  echo Nothing to commit.
  goto :push
)

git commit -m "%MSG%"
if errorlevel 1 (
  echo.
  echo [ERROR] Commit failed.
  exit /b 1
)

:push
echo.
echo === Pushing to origin/main ===
git push
if errorlevel 1 (
  echo.
  echo [ERROR] Push failed.
  echo If this is the first push on a new branch, run:
  echo   git push -u origin HEAD
  exit /b 1
)

echo.
echo Done.
exit /b 0

