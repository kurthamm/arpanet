#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$ROOT/../.." && pwd)"
SIMH_ROOT="$REPO_ROOT/src/linux-ncp/test/simh"
SIGMA="$SIMH_ROOT/BIN/sigma"
KIT_REPO="https://github.com/kenrector/sigma-cpv-kit.git"
ACTION="${1:-}"

usage() {
    cat <<USAGE
Usage: $(basename "$0") <prepare|start|stop|restart|status|console|online|verify>

Runs a real SIMH Sigma 7 with CP-V F00 RAD media from sigma-cpv-kit.
This does not attach a fake UCLA host to the ARPANET.
USAGE
}

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

screen_exists() {
    screen -ls | grep -q '[.]sigma01-cpv[[:space:]]'
}

build_sigma() {
    if [[ ! -x "$SIGMA" ]]; then
        echo "host01-sigma: building SIMH sigma"
        make -C "$SIMH_ROOT" sigma -j2
    fi
    [[ -x "$SIGMA" ]] || fail "SIMH sigma binary is missing: $SIGMA"
}

prepare_kit() {
    mkdir -p "$ROOT/kit-cache" "$ROOT/runtime/f00rad"

    if [[ ! -d "$ROOT/kit-cache/.git" ]]; then
        echo "host01-sigma: fetching sigma-cpv-kit"
        rm -rf "$ROOT/kit-cache"
        git clone --depth 1 "$KIT_REPO" "$ROOT/kit-cache"
    fi

    for file in f00/f00rad/f00rad.tap f00/f00rad/f00rad-system.zip; do
        [[ -f "$ROOT/kit-cache/$file" ]] || fail "missing kit file: $file"
    done

    if [[ ! -f "$ROOT/runtime/f00rad/rad" ||
          ! -f "$ROOT/runtime/f00rad/sys1" ||
          ! -f "$ROOT/runtime/f00rad/sys2" ]]; then
        echo "host01-sigma: extracting CP-V F00 RAD system"
        (cd "$ROOT/runtime/f00rad" && unzip -n "$ROOT/kit-cache/f00/f00rad/f00rad-system.zip")
    fi
}

prepare() {
    build_sigma
    prepare_kit
}

status() {
    if screen_exists; then
        echo "host01-sigma: screen sigma01-cpv present"
    else
        echo "host01-sigma: screen sigma01-cpv absent"
    fi
    ps -eo pid,ppid,pgid,sid,stat,args | grep '[B]IN/sigma .*f00rad.simh' || true
    ss -H -ltnp 2>/dev/null | grep ':4003' || true
}

boot_keyins() {
    local cpv_date cpv_time
    cpv_date="${ARPANET_SIGMA_CPV_DATE:-06/13/86}"
    cpv_time="${ARPANET_SIGMA_CPV_TIME:-$(date +%H:%M)}"

    echo "host01-sigma: sending CP-V boot keyins"
    sleep 2
    screen -S sigma01-cpv -X stuff "$cpv_date"$'\r'
    sleep 1
    screen -S sigma01-cpv -X stuff "$cpv_time"$'\r'
    sleep 2
    screen -S sigma01-cpv -X stuff $'N\r'
    sleep 2
    screen -S sigma01-cpv -X stuff $'N\r'
    sleep 3
    screen -S sigma01-cpv -X stuff $'Y\r'
    sleep 3
    screen -S sigma01-cpv -X stuff $'N\r'
    sleep 4
    screen -S sigma01-cpv -X stuff $'\005'
    sleep 1
    screen -S sigma01-cpv -X stuff $'DEP 114A 0\r'
    sleep 1
    screen -S sigma01-cpv -X stuff $'CONT\r'
    sleep 1
    screen -S sigma01-cpv -X stuff $'\020'
    sleep 1
    screen -S sigma01-cpv -X stuff $'ON 107\r'
    sleep 1
    screen -S sigma01-cpv -X stuff $'\020'
    sleep 1
    screen -S sigma01-cpv -X stuff $'GJOB CONTROL\r'
    sleep 2
    screen -S sigma01-cpv -X stuff $'BUM=1\r'
    sleep 1
    screen -S sigma01-cpv -X stuff $'END\r'
    sleep 1
    screen -S sigma01-cpv -X stuff $'\020'
    sleep 1
    screen -S sigma01-cpv -X stuff $'GJOB RBBAT\r'
}

start() {
    prepare
    if screen_exists; then
        echo "host01-sigma: screen sigma01-cpv already present"
        return
    fi
    mkdir -p "$ROOT/runtime/f00rad"
    echo "host01-sigma: starting SIMH Sigma 7 CP-V F00 RAD"
    (cd "$ROOT" && screen -dmS sigma01-cpv "$SIGMA" f00rad.simh)
    sleep 2
    if [[ "${ARPANET_SIGMA_MANUAL_BOOT:-0}" != "1" ]]; then
        boot_keyins
    fi
    status
}

stop() {
    echo "host01-sigma: stopping"
    if screen_exists; then
        screen -S sigma01-cpv -X stuff $'\020' 2>/dev/null || true
        sleep 1
        screen -S sigma01-cpv -X stuff $'ZAP\r' 2>/dev/null || true
        sleep 75
        screen -S sigma01-cpv -X stuff $'\005quit\r' 2>/dev/null || true
        sleep 5
    fi
    screen -S sigma01-cpv -X quit 2>/dev/null || true
    if ps -eo args | grep -q "[B]IN/sigma f00rad[.]simh"; then
        pkill -TERM -f "$SIGMA f00rad[.]simh" 2>/dev/null || true
        sleep 2
    fi
    echo "host01-sigma: stopped"
}

verify() {
    prepare
    local transcript
    [[ -f "$ROOT/runtime/f00rad/rad" ]] || fail "missing extracted RAD swap device"
    [[ -f "$ROOT/runtime/f00rad/sys1" ]] || fail "missing extracted sys1"
    [[ -f "$ROOT/runtime/f00rad/sys2" ]] || fail "missing extracted sys2"
    "$SIGMA" -v | head -1
    echo "host01-sigma: prepared"
    if screen_exists; then
        if ss -H -ltn 2>/dev/null | grep -q ':4003'; then
            echo "host01-sigma: mux port 4003 listening"
        else
            fail "screen exists but mux port 4003 is not listening"
        fi
        if command -v nc >/dev/null 2>&1; then
            transcript="$({ sleep 1; printf '\r'; sleep 2; } | timeout 8 nc 127.0.0.1 4003 2>&1 | tr -d '\000' || true)"
            printf '%s\n' "$transcript" | sed -n '1,12p'
            if grep -q 'LOGON PLEASE' <<<"$transcript"; then
                echo "host01-sigma: CP-V salutation verified"
            elif grep -q '^!$' <<<"$transcript"; then
                echo "host01-sigma: CP-V command prompt verified"
            else
                echo "host01-sigma: CP-V salutation/prompt not seen; operator setup may still be needed"
            fi
        fi
    fi
}

console() {
    screen -r sigma01-cpv
}

online() {
    screen_exists || fail "sigma01-cpv screen is not running"
    screen -S sigma01-cpv -X stuff $'\020'
    sleep 1
    screen -S sigma01-cpv -X stuff $'ON 107\r'
}

[[ -n "$ACTION" ]] || { usage; exit 2; }
case "$ACTION" in
    prepare) prepare ;;
    start) start ;;
    stop) stop ;;
    restart) stop; start ;;
    status) status ;;
    console) console ;;
    verify) verify ;;
    online) online ;;
    *) usage; exit 2 ;;
esac
