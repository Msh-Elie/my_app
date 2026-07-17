@echo off
REM Start SwitchMoney services (Windows batch script)

echo.
echo ╔════════════════════════════════════════════════╗
echo ║   SwitchMoney Service Starter                   ║
echo ║   Starting Recipient Lookup + Backend          ║
echo ╚════════════════════════════════════════════════╝
echo.

cd /d "%~dp0"

if not exist "backend" (
    echo ERROR: backend folder not found!
    echo Make sure you run this script from the project root
    exit /b 1
)

REM Check if node_modules exists
if not exist "backend\node_modules" (
    echo Installing dependencies...
    cd backend
    call npm install
    cd ..
)

echo.
echo Opening Terminal 1: Recipient Lookup Service - SQLite (port 3003)
echo ═══════════════════════════════════════════════════════════════
start cmd /k "cd backend && echo Starting Recipient Lookup Service (SQLite)... && echo. && node recipient_lookup_service_db.js"

timeout /t 3

echo.
echo Opening Terminal 2: Backend Server (port 3002)
echo ═══════════════════════════════════════════════════
start cmd /k "cd backend && echo Starting Backend Server... && echo. && node server.js"

echo.
echo ✅ Both services are starting!
echo.
echo Available endpoints:
echo   • Lookup Service:  http://localhost:3003/health
echo   • Backend Server:  http://localhost:3002
echo   • Recipient Lookup: POST http://localhost:3003/lookup
echo   • Resolve Recipient: POST http://localhost:3002/api/resolve-recipient
echo.
echo To test lookup:
echo   curl -X POST http://localhost:3003/lookup ^
echo     -H "Content-Type: application/json" ^
echo     -d "{\"phoneNumber\": \"22951469075\", \"provider\": \"MTN BJ\"}"
echo.
echo Press any key to close this window...
pause > nul
