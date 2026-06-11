#!/usr/bin/env bash
set -u -o pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$ROOT/.." && pwd)"
PI_HOST="${ARPANET_PI_HOST:-pi@192.168.50.197}"
PI_TIMEOUT="${ARPANET_PI_TIMEOUT:-8}"
CHECK_PI="${ARPANET_CHECK_PI:-1}"
FAILURES=0
WARNINGS=0

ok() { printf 'OK   %s\n' "$*"; }
warn() { printf 'WARN %s\n' "$*"; WARNINGS=$((WARNINGS + 1)); }
fail() { printf 'FAIL %s\n' "$*"; FAILURES=$((FAILURES + 1)); }
info() { printf 'INFO %s\n' "$*"; }
section() { printf '\n== %s ==\n' "$*"; }

count_lines() {
    sed '/^[[:space:]]*$/d' | wc -l | tr -d ' '
}

process_count() {
    pgrep -fc "$1" 2>/dev/null || true
}

print_matching_processes() {
    ps -eo pid,ppid,pgid,sid,stat,pcpu,args | grep -E "$1" | grep -v grep || true
}

check_repo_state() {
    section "Repository Runtime State"
    local status
    status="$(cd "$REPO_ROOT" && git status --short mini/imp62.simh 2>/dev/null || true)"
    if [[ -n "$status" ]]; then
        warn "site-local runtime config is modified:"
        printf '%s\n' "$status"
    else
        ok "no site-local imp62.simh modification detected"
    fi
}

check_hosted_hosts() {
    section "Hosted ITS Hosts"
    if [[ ! -x "$ROOT/hostctl.sh" ]]; then
        fail "mini/hostctl.sh is missing or not executable"
        return
    fi

    "$ROOT/hostctl.sh" status all

    local verify_output
    verify_output="$($ROOT/hostctl.sh verify all 2>&1)"
    printf '%s\n' "$verify_output"
    for host in 6 70 126; do
        if grep -q "host $host: NCP verified" <<<"$verify_output"; then
            ok "host $host NCP verified"
        else
            fail "host $host NCP verification missing or failed"
        fi
    done
}

check_ncp_pings() {
    section "NCP Reachability"
    local host output rc
    for host in 6 70 126 41; do
        output="$(cd "$ROOT" && timeout 10 env NCP=ncp31 ./ncp-ping -c1 "$host" 2>&1)"
        rc=$?
        printf '%s\n' "$output"
        if [[ $rc -eq 0 ]]; then
            ok "NCP ping host $host"
        else
            fail "NCP ping host $host failed rc=$rc"
        fi
    done
}

check_relay() {
    section "Browser Terminal Relay"
    local relay_count telnet_count
    relay_count="$(process_count 'simh_server.py')"
    if [[ "$relay_count" == "1" ]]; then
        ok "one simh_server.py relay running"
    else
        fail "expected one simh_server.py relay, found $relay_count"
    fi
    print_matching_processes 'simh_server.py'

    telnet_count="$(pgrep -x ncp-telnet 2>/dev/null | count_lines)"
    if [[ "$telnet_count" == "0" ]]; then
        ok "no active ncp-telnet browser/direct sessions"
    else
        warn "$telnet_count ncp-telnet process(es) active; this is OK only during an intentional browser/direct terminal session"
        ps -eo pid,ppid,pgid,sid,stat,args | grep '[n]cp-telnet' || true
    fi
}

check_imp_links() {
    section "IMP Links And Sockets"
    local imp62_count imp06_count link_line
    imp06_count="$(process_count 'h316ov ./imp06.simh')"
    imp62_count="$(process_count 'h316ov ./imp62.simh')"

    [[ "$imp06_count" == "1" ]] && ok "one IMP06 process" || fail "expected one IMP06 process, found $imp06_count"
    [[ "$imp62_count" == "1" ]] && ok "one IMP62 process" || fail "expected one IMP62 process, found $imp62_count"
    print_matching_processes 'h316ov ./imp(06|31|62).simh'

    link_line="$(ss -H -u -a -p | grep '100.105.230.31:11141' | grep ':11262' || true)"
    if [[ -n "$link_line" ]]; then
        ok "IMP62 remote link to Pi IMP41 socket present"
        printf '%s\n' "$link_line"
    else
        fail "IMP62 remote link socket 11262 <-> 100.105.230.31:11141 not found"
    fi
}

check_pi() {
    section "PiDP-10 Remote Node"
    if [[ "$CHECK_PI" == "0" ]]; then
        warn "Pi check disabled by ARPANET_CHECK_PI=0"
        return
    fi

    if ! command -v ssh >/dev/null 2>&1; then
        warn "ssh not available; skipping Pi check"
        return
    fi

    local remote_script output rc
    remote_script='set -u
printf "-- identity --\n"
hostname
printf "-- screens --\n"
screen -ls || true
printf "-- processes --\n"
ps -eo pid,ppid,pgid,sid,stat,pcpu,args | grep -E "pdp10-ka-ncp-pidp|h316-arpa|cbridge|tv11" | grep -v grep || true
printf "-- sockets --\n"
ss -H -u -a -p | grep -E "11141|11262|100.120.170.123" || true
'
    output="$(timeout "$PI_TIMEOUT" ssh -o BatchMode=yes -o ConnectTimeout=5 "$PI_HOST" "bash -s" 2>&1 <<<"$remote_script")"
    rc=$?
    printf '%s\n' "$output"
    if [[ $rc -ne 0 ]]; then
        warn "Pi SSH check failed for $PI_HOST rc=$rc; set ARPANET_CHECK_PI=0 to skip or ARPANET_PI_HOST to override"
        return
    fi

    for name in imp41 pidp10 cbridge tv11; do
        if grep -q "[.]$name[[:space:]]" <<<"$output"; then
            ok "Pi screen $name present"
        else
            fail "Pi screen $name missing"
        fi
    done
    if grep -q '100.105.230.31:11141.*100.120.170.123:11262' <<<"$output"; then
        ok "Pi IMP41 UDP link to Civitae present"
    else
        fail "Pi IMP41 UDP link to Civitae missing"
    fi
}

check_terminal_page() {
    section "Hosted Web Endpoint"
    local status
    status="$(curl -skI --max-time 8 https://arpanet.hamm.me/arpanet_terminal2.html 2>/dev/null | head -1 || true)"
    printf '%s\n' "$status"
    if grep -q ' 200 ' <<<"$status"; then
        ok "terminal page HTTP 200"
    else
        warn "terminal page did not return HTTP 200"
    fi
}

main() {
    section "ARPANET Health Audit"
    info "read-only audit; no processes are changed"
    date
    check_repo_state
    check_hosted_hosts
    check_ncp_pings
    check_relay
    check_imp_links
    check_pi
    check_terminal_page
    section "Summary"
    if [[ $FAILURES -eq 0 && $WARNINGS -eq 0 ]]; then
        ok "health audit clean"
    else
        printf 'FAILURES=%s WARNINGS=%s\n' "$FAILURES" "$WARNINGS"
    fi
    [[ $FAILURES -eq 0 ]]
}

main "$@"
