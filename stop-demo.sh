cd "$(dirname "$0")/mini"
./arpanet stop
cd ..

screen -S web-client   -X quit 2>/dev/null || true
screen -S web-server   -X quit 2>/dev/null || true
screen -S web-http     -X quit 2>/dev/null || true
screen -S waitsconnect -X quit 2>/dev/null || true

echo "Stopped everything. Remaining screen sessions:"
sleep 1
screen -ls
echo
echo "Done."



