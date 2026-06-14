#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/host06-multics"
REPO_ROOT="$(cd "$ROOT/../.." && pwd)"
SIM_REPO="https://gitlab.com/dps8m/dps8m.git"
SIM_TAG="R3.1.0"
QUICKSTART_URL="https://s3.amazonaws.com/eswenson-multics/public/releases/MR12.8/QuickStart_MR12.8.zip"
SCREEN_NAME="host06-multics"
ACTION="${1:-}"
DPS8="$ROOT/sim-cache/src/dps8/dps8"
RUNTIME="$ROOT/runtime"
ZIP="$ROOT/kit-cache/QuickStart_MR12.8.zip"

usage() {
    cat <<USAGE
Usage: $(basename "$0") <prepare|start|stop|restart|status|verify|console>

Runs DPS8M/MR12.8 Multics for MIT-MULTICS host #6.
This is real Multics media, not recovered 1972 MIT H645 storage.
USAGE
}

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

screen_exists() {
    screen -ls | grep -q "[.]$SCREEN_NAME[[:space:]]"
}

build_dps8() {
    if [[ ! -x "$DPS8" ]]; then
        mkdir -p "$ROOT"
        if [[ ! -d "$ROOT/sim-cache/.git" ]]; then
            echo "host06-multics: fetching DPS8M $SIM_TAG"
            rm -rf "$ROOT/sim-cache"
            git clone --depth 1 --branch "$SIM_TAG" "$SIM_REPO" "$ROOT/sim-cache"
        fi
        echo "host06-multics: building DPS8M"
        make -C "$ROOT/sim-cache" -f GNUmakefile -j2
    fi
    [[ -x "$DPS8" ]] || fail "DPS8M binary missing: $DPS8"
}

fetch_quickstart() {
    mkdir -p "$ROOT/kit-cache"
    if [[ ! -f "$ZIP" ]]; then
        echo "host06-multics: downloading MR12.8 QuickStart"
        curl -L --fail -o "$ZIP" "$QUICKSTART_URL"
    fi
}

customize_site_setup() {
    perl -0pi -e '
        s/SYSTEM_NAME="Yoyodyne Propulsion Systems"/SYSTEM_NAME="MIT Project MAC Multics"/;
        s/PROJECT_ADMINISTRATOR="Chiclitz, Clayton"/PROJECT_ADMINISTRATOR="Saltzer, Jerome"/;
        s/ORGANIZATION_ADMINISTRATOR="Yoyodyne"/ORGANIZATION_ADMINISTRATOR="MIT Project MAC"/;
        s/ACCOUNT_NAME="Clayton"/ACCOUNT_NAME="Iccc"/;
        s/ACCOUNT_PASSWORD="password"/ACCOUNT_PASSWORD="iccc2026"/;
        s/NAME="Chiclitz, Clayton"/NAME="Visitor, ICCC"/;
        s/ORGANIZATION="Yoyodyne"/ORGANIZATION="ARPANET ICCC"/;
    ' "$RUNTIME/site_setup.sh"
}

prepare_runtime() {
    if [[ -f "$RUNTIME/root.dsk" && -f "$RUNTIME/MR12.8_boot.ini" ]]; then
        return
    fi
    if ss -H -ltn 2>/dev/null | grep -q ':6180'; then
        fail "TCP port 6180 is in use; stop existing Multics before preparing"
    fi
    rm -rf "$RUNTIME"
    mkdir -p "$RUNTIME"
    unzip -q "$ZIP" -d "$ROOT"
    mv "$ROOT/QuickStart_MR12.8"/* "$RUNTIME/"
    rmdir "$ROOT/QuickStart_MR12.8"
    printf 'sn: 0\n' > "$RUNTIME/serial.txt"
    customize_site_setup
    (cd "$RUNTIME" && ./site_setup.sh > configure.ini)
    echo "host06-multics: running one-time MR12.8 site setup"
    (cd "$RUNTIME" && "$DPS8" configure.ini)
}

prepare() {
    build_dps8
    fetch_quickstart
    prepare_runtime
}

status() {
    if screen_exists; then
        echo "host06-multics: screen $SCREEN_NAME present"
    else
        echo "host06-multics: screen $SCREEN_NAME absent"
    fi
    ps -eo pid,ppid,pgid,sid,stat,args | grep '[d]ps8 MR12[.]8_boot[.]ini' || true
    ss -H -ltnp 2>/dev/null | grep ':6180' || true
}

start() {
    prepare
    if screen_exists; then
        echo "host06-multics: screen $SCREEN_NAME already present"
        return
    fi
    echo "host06-multics: starting DPS8M MR12.8"
    (cd "$RUNTIME" && screen -dmS "$SCREEN_NAME" "$DPS8" MR12.8_boot.ini)
    verify
}

stop() {
    echo "host06-multics: stopping"
    if screen_exists; then
        screen -S "$SCREEN_NAME" -X stuff $'shut\r' 2>/dev/null || true
        sleep 20
        screen -S "$SCREEN_NAME" -X stuff $'die\r' 2>/dev/null || true
        sleep 1
        screen -S "$SCREEN_NAME" -X stuff $'y\r' 2>/dev/null || true
        sleep 5
    fi
    screen -S "$SCREEN_NAME" -X quit 2>/dev/null || true
    pkill -TERM -f "$DPS8 MR12[.]8_boot[.]ini" 2>/dev/null || true
    sleep 2
    pkill -KILL -f "$DPS8 MR12[.]8_boot[.]ini" 2>/dev/null || true
    echo "host06-multics: stopped"
}

verify() {
    prepare
    local transcript deadline=$((SECONDS + 180))
    while (( SECONDS < deadline )); do
        if ss -H -ltn 2>/dev/null | grep -q ':6180'; then
            transcript="$({ sleep 1; printf '\r'; sleep 2; } | timeout 8 nc 127.0.0.1 6180 2>&1 | tr -d '\000' || true)"
            printf '%s\n' "$transcript" | sed -n '1,12p'
            if grep -q 'Multics MR12.8' <<<"$transcript"; then
                echo "host06-multics: Multics salutation verified"
                return
            fi
        fi
        sleep 5
    done
    fail "Multics salutation not seen on TCP 6180"
}

console() {
    screen -r "$SCREEN_NAME"
}

case "$ACTION" in
    prepare) prepare ;;
    start) start ;;
    stop) stop ;;
    restart) stop; start ;;
    status) status ;;
    verify) verify ;;
    console) console ;;
    *) usage; exit 1 ;;
esac
