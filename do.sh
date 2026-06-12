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

# Several ITS hosts reject or stall ARPANET TELNET from the only reliable
# browser-side source NCP (host 037). Route browser terminal sessions through
# SIMH terminal lines while NCP ping remains the ARPANET health check.
if [[ "$COMMAND" =~ ^[lL]$ ]]; then
    case "$DEST" in
        6|006)
            cd ./mini
            exec ./local-host-terminal.py 006 16015
            ;;
        70|106)
            cd ./mini
            exec ./local-host-terminal.py 106 17015
            ;;
        126|176)
            cd ./mini
            exec ./local-host-terminal.py 176 10015
            ;;
        41|051)
            cd ./mini
            exec ./local-host-terminal.py 051 10015 --connect-host 100.105.230.31
            ;;
        11|013)
            cd ./mini
            exec ./local-host-terminal.py 013 2040
            ;;
    esac
fi

# DEST: either 2nd argument or prompt
#DEST="${2:-}"
#if [[ -z "$DEST" ]]; then
#    read -r DEST
#fi

cd ./mini
exec ./dotelnet.sh "$IMP_NUMBER" "$HOST_NUMBER" "$DEST" "$COMMAND"
