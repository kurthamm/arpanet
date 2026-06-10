cd host06
echo $PWD
cp ./006/rp* .
cp ./006/ds* .
echo screen -dmS host06 ../pdp10-ka-fixed ./mini-run
screen -dmS host06 ../pdp10-ka-fixed ./mini-run
cd ..

