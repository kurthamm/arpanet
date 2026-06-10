cd host70
echo $PWD
cp ./106/rp* .
cp ./106/ds* .
echo screen -dmS host70 ../pdp10-ka-fixed ./mini-run
screen -dmS host70 ../pdp10-ka-fixed ./mini-run
cd ..

