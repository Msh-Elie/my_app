#!/bin/bash
# Start SwitchMoney services (Linux/Mac shell script)

echo ""
echo "╔════════════════════════════════════════════════╗"
echo "║   SwitchMoney Service Starter                   ║"
echo "║   Starting Recipient Lookup + Backend          ║"
echo "╚════════════════════════════════════════════════╝"
echo ""

cd "$(dirname "$0")"

if [ ! -d "backend" ]; then
    echo "ERROR: backend folder not found!"
    echo "Make sure you run this script from the project root"
    exit 1
fi

# Check if node_modules exists
if [ ! -d "backend/node_modules" ]; then
    echo "Installing dependencies..."
    cd backend
    npm install
    cd ..
fi

echo ""
echo "Terminal 1: Recipient Lookup Service - SQLite (port 3001)"
echo "╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌"

# Start lookup service in background
(cd backend && node recipient_lookup_service_db.js) &
LOOKUP_PID=$!

sleep 2

echo ""
echo "Terminal 2: Backend Server (port 3000)"
echo "╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌"

# Start backend server in background
(cd backend && node server.js) &
BACKEND_PID=$!

echo ""
echo "✅ Both services are running!"
echo ""
echo "Available endpoints:"
echo "  • Lookup Service:     http://localhost:3003/health"
echo "  • Backend Server:     http://localhost:3002"
echo "  • Recipient Lookup:   POST http://localhost:3003/lookup"
echo "  • Resolve Recipient:  POST http://localhost:3002/api/resolve-recipient"
echo ""
echo "To test lookup:"
echo '  curl -X POST http://localhost:3003/lookup \'
echo '    -H "Content-Type: application/json" \'
echo '    -d "{\"phoneNumber\": \"22951469075\", \"provider\": \"MTN BJ\"}"'
echo ""
echo "PIDs: Lookup=$LOOKUP_PID, Backend=$BACKEND_PID"
echo "To stop: kill $LOOKUP_PID $BACKEND_PID"
echo ""

# Wait for both processes
wait
