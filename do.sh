#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

# SESSION_NUMBER: argument, if given, overrides environment SESSION_NUMBER
if [[ -n "${1-}" ]]; then
    SESSION_NUMBER="$1"
elif [[ -n "${SESSION_NUMBER-}" ]]; then
    :  # use existing environment variable
else
    echo "SESSION_NUMBER not set (argument or environment)" >&2
    exit 1
fi

# TIP-side source NCPs that browser sessions rotate across, one per
# SESSION_NUMBER. Each entry is "IMP HOST_NUMBER FULLHOST", where FULLHOST
# is the ARPANET host number whose NCP socket (mini/ncpFULLHOST) actually
# answers for that IMP/host-index pair -- see the NCPS table in
# mini/arpanet. Most IMPs host a single NCP at host index 0, where FULLHOST
# is just the (zero-padded) IMP number; IMP 10 and IMP 14 each also host a
# second NCP at host index 1 (LL-TX2 on host 74, CMU-10A on host 78) whose
# FULLHOST is not derivable from the IMP number alone.
imp_host_pairs=(
    "12 0 12"
    "31 0 31"
    "4 0 04"
    "10 0 10"
    "10 1 74"
    "13 0 13"
    "14 0 14"
    "14 1 78"
)

# Bounds check (important!)
if (( SESSION_NUMBER < 0 || SESSION_NUMBER >= ${#imp_host_pairs[@]} )); then
    echo "Invalid SESSION_NUMBER: $SESSION_NUMBER" >&2
    exit 1
fi

# Get the pair
pair="${imp_host_pairs[$SESSION_NUMBER]}"

# Split into variables
read -r IMP_NUMBER HOST_NUMBER FULLHOST <<< "$pair"

#echo "S-$SESSION_NUMBER I-$IMP_NUMBER H-$HOST_NUMBER F-$FULLHOST"


# ==================================================
#
# Simulate TIP behaviour: wait for a @L <host> line,
# then use that host number
#
# ==================================================

line=""
while IFS= read -r line || [[ -n "$line" ]]; do
    line=${line%$'\r'}
    if [[ $line =~ ^@([lLoO])[[:space:]]*([0-9]+) ]]; then
        COMMAND="${BASH_REMATCH[1]}"
        DEST="${BASH_REMATCH[2]}"
        break
    fi
done
if [[ -z "${DEST-}" ]]; then
    echo "No @L/@O host command received" >&2
    exit 1
fi
#echo "---> connect $DEST"

# Host 11 is only reachable from AMES ncp16 today (see
# docs/hosted-terminal-fixes.md, open issue); override the rotated source.
case "$DEST" in
    11|013)
        IMP_NUMBER=16
        HOST_NUMBER=0
        FULLHOST=16
        ;;
esac
if [[ ! -S "mini/ncp$FULLHOST" ]]; then
    echo "TIP NCP ncp$FULLHOST is not running; cannot reach host $DEST over the ARPANET" >&2
    exit 1
fi

cd ./mini
exec ./dotelnet.sh "$IMP_NUMBER" "$HOST_NUMBER" "$DEST" "$COMMAND"
