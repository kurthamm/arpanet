echo "======================================"
echo "ARPANET Simh Server"
echo "======================================"
echo ""

# Activate virtual environment
if [ ! -d "venv" ]; then
    echo "Error: Virtual environment not found"
    echo "Please run: python3 -m venv venv && source venv/bin/activate && pip install websockets"
    exit 1
fi

source venv/bin/activate

python3 ws_bridge.py 10018 wss://arpanet.hamm.me/ws &
sleep 1
./vt52 -B telnet localhost 10018

