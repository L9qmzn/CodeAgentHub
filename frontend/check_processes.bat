@echo off
echo Checking for CodeAgentHub related processes...
echo.

echo === Flutter/EXE Processes ===
tasklist /FI "IMAGENAME eq cc_mobile.exe" 2>nul
tasklist /FI "IMAGENAME eq CodeAgentHub.exe" 2>nul

echo.
echo === Backend Node Processes ===
for /f "tokens=2" %%i in ('netstat -ano ^| findstr :8207') do (
    echo Process on port 8207: PID %%i
    tasklist /FI "PID eq %%i" 2>nul
)

echo.
echo === All Node.js Processes ===
tasklist /FI "IMAGENAME eq node.exe" 2>nul

echo.
pause
