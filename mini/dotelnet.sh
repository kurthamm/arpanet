#!/usr/bin/env bash

#echo $1 $2
#echo -----

# Argument 1: own IMP number (default 52)
if [[ "$1" =~ ^[0-9]+$ ]]; then
    IMP=$(printf %02d "$1")
else
    IMP=52
fi

# Argument 2: own host number (default 0)
#if [[ -n "$2" ]]; then
if [[ "$2" == "1" ]]; then
    HOST="-p $2"
else
    HOST=""
fi


# Argument 3: target host (default 126)
if [[ -n "$3" ]]; then
    DEST=$3
else
    DEST=126
fi

#echo "IMP=$IMP"
#echo "HOST=$HOST"
#echo "DEST=$DEST"

TELNET_MODE=""
if [[ "${4-}" =~ ^[oO]$ || "$DEST" == "70" || "$DEST" == "106" ]]; then
    TELNET_MODE="-o"
fi

#echo "NCP=ncp$IMP ./ncp-telnet -c $TELNET_MODE $HOST $DEST"
exec env NCP="ncp$IMP" ./ncp-telnet -c $TELNET_MODE $HOST $DEST
