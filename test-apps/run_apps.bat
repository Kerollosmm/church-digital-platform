@echo off
chcp 65001 > nul
title Church Digital Platform - Test Apps Server (Port 3000)

echo ================================================================
echo   ✝ Church Digital Platform - Local Test Apps Launcher
echo ================================================================

where node >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Node.js is not installed or not in PATH!
    echo Please install Node.js (v18+) to run the test server.
    pause
    exit /b 1
)

echo Starting local server on http://127.0.0.1:3000 ...
start "" "http://127.0.0.1:3000/"

node "%~dp0serve.js" 3000
