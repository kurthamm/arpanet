#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB="$ROOT/host11-ap-lab"
ACTION="${1:-}"

usage() {
    cat <<USAGE
Usage: $(basename "$0") <prepare|status|start|stop|restart|console|verify-parry|verify-ap>

Private Stanford/SU-AI AP/APE restoration lab. This never starts waitsconnect
and never binds the public host 11 ports.
USAGE
}

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

tcp_ports() {
    echo "1125 2140 2141 2142 2143"
}

screen_exists() {
    screen -ls | grep -q "[.]host11-ap-lab[[:space:]]"
}

is_lab_pid() {
    local pid="$1" cmdline
    cmdline="$(tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null || true)"
    grep -Eq 'pdp10-ka ./waits-ap-lab\.ini|waits-ap-lab\.ini' <<<"$cmdline"
}

port_pids() {
    local port pid
    for port in $(tcp_ports); do
        lsof -nP -tiTCP:"$port" -sTCP:LISTEN 2>/dev/null || true
    done | sort -n -u | while read -r pid; do
        [[ -z "$pid" ]] && continue
        if is_lab_pid "$pid"; then
            echo "$pid"
        fi
    done
}

print_owners() {
    local pids
    pids="$(port_pids | tr '\n' ' ')"
    if [[ -z "${pids// }" ]]; then
        echo "host 11 AP lab: no owned lab ports"
        return
    fi
    echo "host 11 AP lab: owned lab ports by PID(s): $pids"
    ps -o pid,ppid,pgid,sid,stat,args -p $pids 2>/dev/null || true
}

write_lab_ini() {
    cat >"$LAB/waits-ap-lab.ini" <<'EOF'
echo
echo =====================================================================
echo
SET CONSOLE TELNET=BUFFERED=44
set cons -u telnet=1125
echo
echo host11 AP lab console: telnet localhost 1125
echo lab DCS lines: 2140-2143
echo
echo =====================================================================
echo
set throttle 30%

set cr disable
set cp disable
set dpa disable
set dpb disable
set rpa disable
set rpb disable
set tua disable
set fha disable
set dt disable
set dc disable
set mta disable
set pmp enable
set mtc enable
set dtc enable
set dcs enable
set dct enable
set dkb enable
set iii disable
set pclk enable
set cpu waits maoff
set mtc dct=02
set dtc dct=01
set pmp0 dev=60
set pmp0 type=3330-2
set pmp1 type=3330-2
set pmp2 type=3330-2
set lpt waits
at lpt -n wa-ap-lab.log
at pmp0 SYS000.ckd
at pmp1 SYS001.ckd
at pmp2 SYS002.ckd
at dcs -U line=0,2140
set DCS0 log=line0-ap-lab.log
at dcs -U line=1,2141
set DCS1 log=line1-ap-lab.log
at dcs -U line=2,2142
at dcs -U line=3,2143
load -d SYSTEM.DMP.K17
go 200
EOF
}

prepare_lab() {
    mkdir -p "$LAB"
    for file in SYS000.ckd SYS001.ckd SYS002.ckd SYSTEM.DMP.K17 pdp10-ka; do
        [[ -f "$ROOT/host11/$file" ]] || fail "missing live host11 file: $file"
        cp -p "$ROOT/host11/$file" "$LAB/$file"
    done
    write_lab_ini
    echo "host 11 AP lab: prepared isolated copy in $LAB"
}

status_lab() {
    if screen_exists; then
        echo "host 11 AP lab: screen present"
    else
        echo "host 11 AP lab: screen absent"
    fi
    print_owners
}

stop_lab() {
    local pid pgid
    echo "host 11 AP lab: stopping"
    screen -S host11-ap-lab -X quit 2>/dev/null || true
    sleep 1
    while read -r pid; do
        [[ -z "$pid" ]] && continue
        pgid="$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ')"
        [[ -n "$pgid" ]] && kill -TERM "-$pgid" 2>/dev/null || true
    done < <(port_pids)
    sleep 2
    while read -r pid; do
        [[ -z "$pid" ]] && continue
        pgid="$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ')"
        [[ -n "$pgid" ]] && kill -KILL "-$pgid" 2>/dev/null || true
    done < <(port_pids)
    echo "host 11 AP lab: stopped"
}

start_lab() {
    [[ -f "$LAB/waits-ap-lab.ini" ]] || prepare_lab
    [[ -z "$(port_pids)" ]] || fail "lab ports already owned; run stop first"
    if screen_exists; then
        fail "screen host11-ap-lab already exists; run stop first"
    fi
    echo "host 11 AP lab: starting private simulator"
    (cd "$LAB" && screen -dmS host11-ap-lab ./pdp10-ka ./waits-ap-lab.ini)
}

wait_port() {
    local port="$1" deadline=$((SECONDS + 60))
    while (( SECONDS < deadline )); do
        if lsof -nP -tiTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done
    return 1
}

console_lab() {
    wait_port 2140 || fail "lab DCS line 2140 is not listening"
    nc 127.0.0.1 2140
}

expect_line() {
    local script="$1"
    wait_port 2140 || fail "lab DCS line 2140 is not listening"
    expect -f "$script"
}

verify_parry() {
    local tmp
    tmp="$(mktemp)"
    trap 'rm -f "$tmp"' RETURN
    cat >"$tmp" <<'EOF'
log_user 1
set timeout 45
proc send_slow {text} {
  foreach ch [split $text ""] {
    send -- $ch
    after 250
  }
}
spawn telnet 127.0.0.1 2140
expect {
  -re {[\r\n]\.} {}
  -re {CON-TELLOGIN|JOB|STANFORD|#} {
    send "\003"
    exp_continue
  }
  -re {Connected to the KA-10 simulator DCS device} {
    sleep 5
    send "\003"
    exp_continue
  }
  timeout { puts "TIMEOUT initial"; exit 1 }
}
sleep 1
send_slow "R PARRY\r"
expect {
  -re {Please type your Project|JOB [0-9]+.*Stanford|NEW.*GAME|WOULD YOU LIKE|PARANOID|READY:} { puts "PARRY_OK" }
  -re {CAN'T|NOT FOUND} { puts "PARRY_FAIL"; exit 2 }
  eof { puts "PARRY_EOF"; exit 3 }
  timeout { puts "TIMEOUT parry"; exit 1 }
}
catch {send "\003"}
sleep 1
catch {send "KJOB\r"}
sleep 1
catch {send "\035"}
sleep 1
catch {send "quit\r"}
catch {expect eof}
EOF
    expect_line "$tmp"
}

verify_ap() {
    local tmp
    tmp="$(mktemp)"
    trap 'rm -f "$tmp"' RETURN
    cat >"$tmp" <<'EOF'
log_user 1
set timeout 90
proc send_slow {text} {
  foreach ch [split $text ""] {
    send -- $ch
    after 250
  }
}
spawn telnet 127.0.0.1 2140
expect {
  -re {[\r\n]\.} {}
  -re {CON-TELLOGIN|JOB|STANFORD|#} {
    send "\003"
    exp_continue
  }
  -re {Connected to the KA-10 simulator DCS device} {
    sleep 5
    send "\003"
    exp_continue
  }
  timeout { puts "TIMEOUT initial"; exit 1 }
}
sleep 1
send_slow "R HOT\r"
expect {
  -re {ASSOCIATED PRESS} { puts "HOT_OK" }
  -re {Please type your Project and Programmer name\.} { puts "HOT_PROMPT_ONLY"; exit 8 }
  -re {HOT\\.DMP NOT FOUND|CAN'T|CANT|NO SUCH} { puts "HOT_FAIL"; exit 2 }
  eof { puts "HOT_EOF"; exit 6 }
  timeout { puts "HOT_TIMEOUT"; exit 3 }
}
catch {send "\003"}
sleep 1
send_slow "R APE\r"
expect {
  -re {KEYWORD EXPRESSION:} { puts "APE_OK" }
  -re {SUPER HORRENDOUS ERROR|APE\\.DMP NOT FOUND|CAN'T|CANT|NO SUCH} { puts "APE_FAIL"; exit 4 }
  eof { puts "APE_EOF"; exit 7 }
  timeout { puts "APE_TIMEOUT"; exit 5 }
}
catch {send "\003"}
sleep 1
catch {send "KJOB\r"}
sleep 1
catch {send "\035"}
sleep 1
catch {send "quit\r"}
catch {expect eof}
EOF
    expect_line "$tmp"
}

case "$ACTION" in
    prepare) prepare_lab ;;
    status) status_lab ;;
    start) start_lab ;;
    stop) stop_lab ;;
    restart) stop_lab; start_lab ;;
    console) console_lab ;;
    verify-parry) verify_parry ;;
    verify-ap) verify_ap ;;
    *) usage; exit 2 ;;
esac
