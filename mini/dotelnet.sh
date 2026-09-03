#!/usr/bin/env bash
set -euo pipefail

#echo $1 $2
#echo -----

# Argument 1: own IMP number (default 52)
if [[ "$1" =~ ^[0-9]+$ ]]; then
    IMP=$(printf %02d "$1")
else
    IMP=52
fi

# Argument 2: own host index on the source IMP (0 or 1). Historically this
# also forced "-p 1" (destination socket 1, old-style telnet ICP) on the
# client for host-index-1 sources; that's wrong for our FEP-backed
# destinations, which all listen on socket 23 (new telnet) regardless of
# which source TIP is connecting -- old-vs-new destination selection is
# handled below by TELNET_MODE, keyed on DEST, not on the source host
# index. See NCP_FULLHOST below for what $2 actually determines: the
# source NCP socket name.

# Argument 3: target host (default 126)
if [[ -n "$3" ]]; then
    DEST=$3
else
    DEST=126
fi

# Normalize octal-style ARPANET host spelling used in the UI/docs.
# ncp-telnet expects decimal input and prints octal host numbers.
if [[ "$DEST" == "051" ]]; then
    DEST=41
fi

#echo "IMP=$IMP"
#echo "DEST=$DEST"

TELNET_MODE=""
if [[ "${4-}" =~ ^[oO]$ || "$DEST" == "70" || "$DEST" == "106" || "$DEST" == "41" || "$DEST" == "051" ]]; then
    TELNET_MODE="-o"
fi

# TIP-side NCP socket for this IMP/host-index pair. Most IMPs host a
# single NCP at host index 0, whose full ARPANET host number is just the
# (zero-padded) IMP number. IMP 10 and IMP 14 each also host a second NCP
# at host index 1 (host 74, host 78) that is not derivable from the IMP
# number alone -- see the NCPS table in mini/arpanet.
case "$1 $2" in
    "10 1") NCP_FULLHOST=74 ;;
    "14 1") NCP_FULLHOST=78 ;;
    *)      NCP_FULLHOST="$IMP" ;;
esac

#echo "NCP=ncp$NCP_FULLHOST ./ncp-telnet -c $TELNET_MODE $DEST"
exec env NCP="ncp$NCP_FULLHOST" ./ncp-telnet -c $TELNET_MODE "$DEST"
