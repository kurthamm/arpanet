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

# Load gate for staged startup: don't launch the next host until the 1-minute
# load average falls back to this, so we never cold-start every heavy guest OS at
# once (that boot-storm saturates a small box and stalls IMP mesh convergence).
# Scaled to the box (cores + half); override with ARPANET_LOAD_GATE.
LOAD_GATE="${ARPANET_LOAD_GATE:-$(( $(nproc) + $(nproc)/2 ))}"

# Wait until the 1-min load average is <= LOAD_GATE, or until a bounded cap (so a
# genuinely busy box still makes progress rather than hanging forever).
wait_load_settle() {
    local max="${1:-150}" waited=0 load
    while (( waited < max )); do
        load="$(cut -d. -f1 /proc/loadavg)"
        (( load <= LOAD_GATE )) && return 0
        sleep 5; waited=$((waited + 5))
    done
    warn "load still >${LOAD_GATE} after ${max}s (now $(cut -d' ' -f1 /proc/loadavg)); proceeding"
    return 0
}

# Start one host, then wait for the box to settle before returning.
start_host_staged() {
    local label="$1"; shift
    log "  staged start: ${label} (load $(cut -d' ' -f1 /proc/loadavg), gate ${LOAD_GATE})"
    "$@" || true
    wait_load_settle 150
}

# FEP-bridged host OSes (Sigma, Multics, WAITS): their Linux FEP bridge
# reconnects to the IMP whenever the NCP socket appears, so they can boot in any
# order relative to the IMPs. Started BEFORE the IMP farm.
start_fep_hosts() {
    start_host_staged "UCLA Sigma #1"       "$ROOT/host01-sigma/host01-sigmactl.sh" start
    start_host_staged "MIT Multics #6"      "$ROOT/host06-multicsctl.sh" start
    start_host_staged "Stanford WAITS #11"  "$ROOT/host11ctl.sh" start 11
}

# Native-NCP ITS hosts: ITS CANNOT reconnect to an IMP after the fact -- it only
# marries an IMP by booting INTO a running one. So these must start AFTER the IMP
# farm is up (not rely on cold-start timing overlap, which staging breaks).
start_its_hosts() {
    start_host_staged "MIT-DM #70 (ITS)"    "$ROOT/hostctl.sh" start 70
    start_host_staged "HILTON-KA1 #126"     "$ROOT/hostctl.sh" start 126
    start_host_staged "MIT-AI #134 (ITS)"   "$ROOT/hostctl.sh" start 134
    start_host_staged "MIT-ML #198 (ITS)"   "$ROOT/hostctl.sh" start 198
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

# --- self-heal reconciliation (host-side orchestration only; never touches the guest) ---
#
# ITS host -> (imp, imp-side udp port, host-side udp port). An ITS host is only "on
# the net" once it has NCP-married its IMP over that UDP pair. Two distinct failure
# modes, distinguished precisely so we never over-react:
#
#   * host down BUT imp-side socket present  -> IMP interface is fine; the ITS just
#     needs a fresh boot to (re)marry. Cheap, host-local, safe.
#   * host down AND imp-side socket ABSENT   -> the IMP lost the boot-race attaching
#     that host interface (see imp06 hi4: the busiest IMP brings up 4 host ifaces at
#     once and the last can fail to attach). The only fix is restarting the IMP --
#     but ONLY with every host peer present, because a peerless hi interface trips
#     hi_link_error and crashes the fresh IMP. So we ensure all the IMP's host KAs
#     are running first, restart the IMP, then fresh-boot its ITS hosts to marry.
#
# A slow-but-healthy boot keeps its imp-side socket attached, so it is NEVER mistaken
# for the detached-interface case -- that is what makes auto-restart of an IMP safe.
its_topology() {
    # host imp imp_port host_port
    cat <<'TOPO'
70 6 21061 21062
126 62 21621 21622
134 6 22061 22062
198 6 23061 23062
TOPO
}

impside_up() { ss -Huna 2>/dev/null | grep -qE "127\.0\.0\.1:$1\b"; }
hostside_up() { ss -Huna 2>/dev/null | grep -qE "127\.0\.0\.1:$1\b"; }
screen_present() { screen -ls 2>/dev/null | grep -qE "[.]host$1[[:space:]]"; }

# Give a genuinely-down host a bounded chance to come up on its own before deciding.
host_is_up() {
    local host="$1" deadline=$((SECONDS + "${2:-0}"))
    while :; do
        "$ROOT/hostctl.sh" isup "$host" >/dev/null 2>&1 && return 0
        (( SECONDS < deadline )) || return 1
        sleep 5
    done
}

reconcile() {
    local host imp iport hport
    declare -A imp_restart=()
    declare -A reboot_host=()

    log "== classify ITS hosts =="
    while read -r host imp iport hport; do
        [[ -n "$host" ]] || continue
        if host_is_up "$host" 60; then
            ok "host $host on the net (imp $imp)"
        elif impside_up "$iport"; then
            warn "host $host down, imp $imp interface UP -> fresh-boot host"
            reboot_host[$host]=1
        else
            warn "host $host down, imp $imp interface DETACHED -> imp $imp needs restart"
            imp_restart[$imp]=1
        fi
    done < <(its_topology)

    # Heal detached IMP interfaces: ensure every host peer of the IMP is present
    # (so the restart cannot crash on a peerless interface), restart the IMP, then
    # fresh-boot that IMP's ITS hosts so they re-marry.
    for imp in "${!imp_restart[@]}"; do
        log "== self-heal imp $imp =="
        while read -r host himp iport hport; do
            [[ "$himp" == "$imp" ]] || continue
            if screen_present "$host"; then
                ok "  peer host $host KA present"
            else
                log "  starting host $host KA (peer must be present before imp restart)"
                "$ROOT/hostctl.sh" start "$host" || true
            fi
        done < <(its_topology)
        # let freshly-started KAs bind their host-side UDP socket
        local waited=0
        while (( waited < 30 )); do
            local all=1
            while read -r host himp iport hport; do
                [[ "$himp" == "$imp" ]] || continue
                hostside_up "$hport" || all=0
            done < <(its_topology)
            (( all == 1 )) && break
            sleep 3; waited=$((waited + 3))
        done
        log "  restarting imp $imp"
        "$ROOT/impctl.py" restart "$imp" >/dev/null 2>&1 || true
        wait_imp_running "$imp" || warn "imp $imp did not report RUNNING"
        sleep 10   # mesh reconverge
        # every ITS host on this imp must fresh-boot to complete the 1822 handshake
        while read -r host himp iport hport; do
            [[ "$himp" == "$imp" ]] || continue
            reboot_host[$host]=1
        done < <(its_topology)
    done

    for host in "${!reboot_host[@]}"; do
        log "== fresh-boot host $host =="
        "$ROOT/hostctl.sh" stop "$host" || true
        "$ROOT/hostctl.sh" start "$host" || true
    done

    # final verdict
    log ""
    log "== reconcile result =="
    while read -r host imp iport hport; do
        [[ -n "$host" ]] || continue
        if host_is_up "$host" 240; then
            ok "host $host on the net"
        else
            fail "host $host still down after reconcile"
        fi
    done < <(its_topology)

    # FEP-bridged hosts self-reconnect; just nudge their controller if down.
    "$ROOT/host06-multicsctl.sh" verify >/dev/null 2>&1 && ok "host 6 Multics on the net" \
        || { warn "host 6 Multics down -> restart"; sudo systemctl restart arpanet-host06-multics.service || fail "host 6 restart"; }
}

usage() {
    cat <<USAGE
Usage: $(basename "$0") [recover|verify|reconcile]

recover    Stop hosted systems, restart the NOC/IMP service, wait for core IMPs
           and source NCPs, then start hosted systems and verify them.
verify     Read-only verification of the ordered runtime layers.
reconcile  Self-heal: bring any down host back on the net, restarting an IMP
           (peers-present, crash-safe) only when its host interface detached.
USAGE
}

action="${1:-recover}"
case "$action" in
    recover)
        try_step "Preflight cleanup of stale artifacts" preflight_cleanup
        run_step "Start FEP-bridged host OSes (Sigma/Multics/WAITS)" start_fep_hosts
        run_step "Start NOC/IMP service" sudo systemctl start arpanet-noc.service
        try_step "NOC service active" systemctl is-active --quiet arpanet-noc.service
        run_step "Let the IMP farm settle" wait_load_settle 180
        try_step "IMP 06 MIT running" wait_imp_running 6
        try_step "IMP 11 Stanford running" wait_imp_running 11
        try_step "IMP 31 CCA running" wait_imp_running 31
        try_step "IMP 62 Hilton running" wait_imp_running 62
        try_step "NCP31 running" verify_ncp_ready 31
        try_step "NCP16 running" verify_ncp_ready 16
        # ITS hosts marry only by booting INTO a running IMP -- start them now that
        # the farm is up, not before it (deterministic; not timing-dependent).
        run_step "Start ITS hosts into the running IMPs" start_its_hosts
        run_step "Verify hosted systems" verify_hosts
        ;;
    reconcile)
        run_step "Self-heal reconciliation" reconcile
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
