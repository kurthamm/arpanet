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
# Use a single known-good source NCP for browser TELNET sessions.  Rotating
# through historical TIP sources makes hosted-browser behavior depend on source
# NCPs that are absent or unreliable in the DigitalOcean deployment.
IMP_NUMBER=31
HOST_NUMBER=0

#echo "S-$SESSION_NUMBER I-$IMP_NUMBER H-$HOST_NUMBER"


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

# TIP-side NCP used as the visitor's source host. Host 11 is only reachable
# from AMES ncp16 today (see docs/hosted-terminal-fixes.md, open issue).
case "$DEST" in
    11|013) IMP_NUMBER=16 ;;
    *)      IMP_NUMBER=31 ;;
esac
HOST_NUMBER=0
if [[ ! -S "mini/ncp$IMP_NUMBER" ]]; then
    echo "TIP NCP ncp$IMP_NUMBER is not running; cannot reach host $DEST over the ARPANET" >&2
    exit 1
fi

# DEST: either 2nd argument or prompt
#DEST="${2:-}"
#if [[ -z "$DEST" ]]; then
#    read -r DEST
#fi

cd ./mini
exec ./dotelnet.sh "$IMP_NUMBER" "$HOST_NUMBER" "$DEST" "$COMMAND"
