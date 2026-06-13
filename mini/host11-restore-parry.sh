#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_REPO="https://github.com/larsbrinkhoff/sailing-on-arpanet.git"
SOURCE_COMMIT="c5e29a27a4dd8db03a8b2dbc79082f2612ae30ee"
CACHE_DIR="${ARPANET_HOST11_PARRY_CACHE:-$HOME/arpanet-runtime-cache/sailing-on-arpanet}"
BACKUP_ROOT="${ARPANET_HOST11_BACKUP_DIR:-$HOME/arpanet-runtime-backups}"
RESTART=0

usage() {
    cat <<USAGE
Usage: $(basename "$0") [--restart]

Restores Stanford/SU-AI host 11 WAITS packs with the PARRY support files from
Lars Brinkhoff's sailing-on-arpanet restoration.

Source: $SOURCE_REPO
Commit: $SOURCE_COMMIT

Without --restart, host 11 must already be stopped.
With --restart, the script stops host 11, restores the packs, and starts it.
USAGE
}

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --restart) RESTART=1 ;;
        -h|--help) usage; exit 0 ;;
        *) usage; exit 2 ;;
    esac
    shift
done

screen_exists() {
    local name="$1"
    screen -ls | grep -q "[.]$name[[:space:]]"
}

host11_running() {
    screen_exists host11 || screen_exists waitsconnect
}

prepare_source() {
    mkdir -p "$(dirname "$CACHE_DIR")"
    if [[ ! -d "$CACHE_DIR/.git" ]]; then
        echo "host 11 PARRY: cloning restoration source"
        git clone "$SOURCE_REPO" "$CACHE_DIR"
    fi
    git -C "$CACHE_DIR" fetch --tags origin
    git -C "$CACHE_DIR" checkout --detach "$SOURCE_COMMIT"
    for file in SYS000.ckd.bz2 SYS001.ckd.bz2 SYS002.ckd.bz2; do
        [[ -f "$CACHE_DIR/$file" ]] || fail "missing restored pack: $CACHE_DIR/$file"
    done
}

backup_current_packs() {
    local stamp backup_dir
    stamp="$(date -u +%Y%m%dT%H%M%SZ)"
    backup_dir="$BACKUP_ROOT/host11-before-parry-$stamp"
    mkdir -p "$backup_dir"
    cp -p "$ROOT/host11"/SYS*.ckd "$backup_dir"/
    echo "$SOURCE_REPO" >"$backup_dir/parry-source.txt"
    echo "$SOURCE_COMMIT" >>"$backup_dir/parry-source.txt"
    echo "host 11 PARRY: backed up current packs to $backup_dir"
}

restore_packs() {
    local tmp
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' RETURN
    echo "host 11 PARRY: extracting restored WAITS packs"
    bunzip2 -c "$CACHE_DIR/SYS000.ckd.bz2" >"$tmp/SYS000.ckd"
    bunzip2 -c "$CACHE_DIR/SYS001.ckd.bz2" >"$tmp/SYS001.ckd"
    bunzip2 -c "$CACHE_DIR/SYS002.ckd.bz2" >"$tmp/SYS002.ckd"
    cp -p "$tmp"/SYS*.ckd "$ROOT/host11"/
    echo "host 11 PARRY: restored SYS000.ckd SYS001.ckd SYS002.ckd"
}

if [[ "$RESTART" == "1" ]]; then
    "$ROOT/host11ctl.sh" stop 11
elif host11_running; then
    fail "host 11 is running; stop it first or pass --restart"
fi

prepare_source
backup_current_packs
restore_packs

if [[ "$RESTART" == "1" ]]; then
    "$ROOT/host11ctl.sh" start 11
    "$ROOT/host11ctl.sh" status 11
fi
