#!/usr/bin/env bash
set -u -o pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FAILURES=0

log() { printf '%s\n' "$*"; }
ok() { printf 'OK   %s\n' "$*"; }
warn() { printf 'WARN %s\n' "$*"; }
fail() { printf 'FAIL %s\n' "$*"; FAILURES=$((FAILURES + 1)); }

run_step() {
    local label="$1"
    shift
    log ""
    log "== $label =="
    "$@"
}

try_step() {
    local label="$1"
    shift
    log ""
    log "== $label =="
    if "$@"; then
        ok "$label"
    else
        fail "$label"
    fi
}

stop_hosts() {
    "$ROOT/host11ctl.sh" stop 11 || true
    "$ROOT/hostctl.sh" stop all || true
    ARPANET_FAST_STOP=1 "$ROOT/host01-sigma/host01-sigmactl.sh" stop || true
    "$ROOT/host06-multicsctl.sh" stop || true
}

cleanup_core_artifacts() {
    sudo systemctl stop arpanet-noc.service || true
    pkill -9 -f '^[.]/h316ov [.](/)?imp[0-9][0-9][.]simh' 2>/dev/null || true
    pkill -9 -f '^[.]/h316ov [.](/)?imp[0-9][0-9][.]local[.]simh' 2>/dev/null || true
    pkill -9 -f '^[.]/ncpdov localhost' 2>/dev/null || true
    pkill -9 -f '^[.]/ncpd localhost' 2>/dev/null || true
    sleep 1
    find "$ROOT" -maxdepth 1 -type s -name 'ncp[0-9]*' -delete
}

assert_no_core_artifacts() {
    local output
    output="$(ps -eo pid,ppid,pgid,sid,stat,args | grep -E '[.]/h316ov [.](/)?imp|[.]/ncpdov localhost|[.]/ncpd localhost' || true)"
    if [[ -n "$output" ]]; then
        printf '%s\n' "$output"
        return 1
    fi
    output="$(find "$ROOT" -maxdepth 1 -type s -name 'ncp[0-9]*' -print)"
    if [[ -n "$output" ]]; then
        printf '%s\n' "$output"
        return 1
    fi
    ok "no stale IMP/NCP processes or NCP sockets"
}

assert_no_duplicate_screens() {
    local output
    output="$(screen -ls | awk '
        /\t[0-9]+[.]/ {
            name = $1
            sub(/^[0-9]+[.]/, "", name)
            count[name]++
        }
        END {
            for (name in count) {
                if (count[name] > 1) {
                    printf "%s %d\n", name, count[name]
                }
            }
        }
    ')"
    if [[ -n "$output" ]]; then
        printf '%s\n' "$output"
        return 1
    fi
    ok "no duplicate screen sessions"
}

preflight_cleanup() {
    stop_hosts
    cleanup_core_artifacts
    assert_no_core_artifacts
    assert_no_duplicate_screens
}

start_hosts() {
    "$ROOT/host01-sigma/host01-sigmactl.sh" start || true
    "$ROOT/host06-multicsctl.sh" start || true
    "$ROOT/hostctl.sh" start 70 || true
    "$ROOT/hostctl.sh" start 126 || true
    "$ROOT/hostctl.sh" start 134 || true
    "$ROOT/hostctl.sh" start 198 || true
    "$ROOT/host11ctl.sh" start 11 || true
}

wait_imp_running() {
    local imp="$1" deadline=$((SECONDS + 90)) output
    while (( SECONDS < deadline )); do
        output="$("$ROOT/impctl.py" status "$imp" 2>&1 || true)"
        if grep -q 'State:[[:space:]]*RUNNING' <<<"$output"; then
            ok "IMP $imp running"
            return 0
        fi
        sleep 3
    done
    printf '%s\n' "$output"
    return 1
}

verify_ncp_ready() {
    local host="$1" deadline=$((SECONDS + 60)) output socket_host
    socket_host="$((10#$host))"
    while (( SECONDS < deadline )); do
        output="$("$ROOT/impctl.py" 2>&1 || true)"
        if grep -Eq "^[[:space:]]*$socket_host[[:space:]].*[[:space:]]RUNNING[[:space:]]" <<<"$output" &&
           [[ -S "$ROOT/ncp$socket_host" ]]; then
            ok "NCP $host running with socket ncp$socket_host"
            return 0
        fi
        sleep 3
    done
    printf '%s\n' "$output" | sed -n '/NCPs:/,$p'
    [[ -S "$ROOT/ncp$socket_host" ]] || echo "missing socket: $ROOT/ncp$socket_host"
    return 1
}

require_udp_pair() {
    local label="$1" a="$2" b="$3" output
    output="$(ss -H -u -a -p | grep -E "$a.*$b|$b.*$a" || true)"
    if [[ -n "$output" ]]; then
        ok "$label UDP $a <-> $b"
        printf '%s\n' "$output"
        return 0
    fi
    echo "missing UDP pair for $label: $a <-> $b"
    return 1
}

require_tcp_listen() {
    local label="$1" port="$2" output
    output="$(ss -H -ltnp | grep -E "[:.]$port[[:space:]]" || true)"
    if [[ -n "$output" ]]; then
        ok "$label TCP $port listening"
        printf '%s\n' "$output"
        return 0
    fi
    echo "missing TCP listener for $label: $port"
    return 1
}

verify_hosts() {
    local output rc
    output="$("$ROOT/host06-multicsctl.sh" verify 2>&1)"
    rc=$?
    printf '%s\n' "$output"
    [[ $rc -eq 0 ]] && ok "host 6 Multics terminal" || fail "host 6 Multics terminal"

    "$ROOT/hostctl.sh" status all
    "$ROOT/host11ctl.sh" status 11

    require_udp_pair "MIT-DM #70" "21061" "21062" || fail "MIT-DM #70 UDP link"
    require_udp_pair "HILTON-KA1 #126" "21621" "21622" || fail "HILTON-KA1 #126 UDP link"
    require_udp_pair "MIT-AI #134" "22061" "22062" || fail "MIT-AI #134 UDP link"
    require_udp_pair "MIT-ML #198" "23061" "23062" || fail "MIT-ML #198 UDP link"
    require_udp_pair "SU-AI #11" "20111" "20112" || fail "SU-AI #11 UDP link"

    require_tcp_listen "UCLA Sigma #1" "4003" || fail "UCLA Sigma #1 terminal listener"
    require_tcp_listen "MIT-MULTICS #6" "6180" || fail "MIT-MULTICS #6 terminal listener"
    require_tcp_listen "MIT-DM #70" "17015" || fail "MIT-DM #70 terminal listener"
    require_tcp_listen "HILTON-KA1 #126" "10015" || fail "HILTON-KA1 #126 terminal listener"
    require_tcp_listen "MIT-AI #134" "18015" || fail "MIT-AI #134 terminal listener"
    require_tcp_listen "MIT-ML #198" "19015" || fail "MIT-ML #198 terminal listener"
}

usage() {
    cat <<USAGE
Usage: $(basename "$0") [recover|verify]

recover  Stop hosted systems, restart the NOC/IMP service, wait for core IMPs
         and source NCPs, then start hosted systems and verify them.
verify   Read-only verification of the ordered runtime layers.
USAGE
}

action="${1:-recover}"
case "$action" in
    recover)
        try_step "Preflight cleanup of stale artifacts" preflight_cleanup
        run_step "Start hosted endpoint systems" start_hosts
        run_step "Start NOC/IMP service" sudo systemctl start arpanet-noc.service
        try_step "NOC service active" systemctl is-active --quiet arpanet-noc.service
        try_step "IMP 06 MIT running" wait_imp_running 6
        try_step "IMP 11 Stanford running" wait_imp_running 11
        try_step "IMP 31 CCA running" wait_imp_running 31
        try_step "IMP 62 Hilton running" wait_imp_running 62
        try_step "NCP31 running" verify_ncp_ready 31
        try_step "NCP16 running" verify_ncp_ready 16
        run_step "Verify hosted systems" verify_hosts
        ;;
    verify)
        try_step "NOC service active" systemctl is-active --quiet arpanet-noc.service
        try_step "IMP 06 MIT running" wait_imp_running 6
        try_step "IMP 11 Stanford running" wait_imp_running 11
        try_step "IMP 31 CCA running" wait_imp_running 31
        try_step "IMP 62 Hilton running" wait_imp_running 62
        try_step "NCP31 running" verify_ncp_ready 31
        try_step "NCP16 running" verify_ncp_ready 16
        run_step "Verify hosted systems" verify_hosts
        ;;
    *)
        usage
        exit 2
        ;;
esac

log ""
if [[ "$FAILURES" -eq 0 ]]; then
    ok "runtime recovery/verification clean"
else
    fail "$FAILURES recovery/verification step(s) failed"
fi
exit "$FAILURES"
