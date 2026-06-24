@echo off
chcp 65001 >nul 2>&1
title Claude Code Deploy

cd /d "%~dp0"

PowerShell -NoProfile -ExecutionPolicy Bypass -File "%~dp0deploy.ps1"

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo Deploy failed. Check logs\ directory for details.
    echo.
    pause
)
