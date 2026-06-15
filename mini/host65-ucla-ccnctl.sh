#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/host65-ucla-ccn"
ACTION="${1:-}"
ARCHIVE_URL="https://cbttape.org/ftp/OS360/TURNKEYMVTJAY1.zip"
ARCHIVE="$ROOT/kit-cache/TURNKEYMVTJAY1.zip"
RUNTIME="$ROOT/runtime"
MVT="$RUNTIME/os360mvt"
LOGS="$ROOT/logs"
TRANSCRIPTS="$ROOT/transcripts"
FRONTDOOR_PORT="${HOST65_FRONTDOOR_PORT:-16515}"
HERCULES_CONSOLE_PORT="${HOST65_HERCULES_CONSOLE_PORT:-3271}"
HERCULES_HTTP_PORT="${HOST65_HERCULES_HTTP_PORT:-8651}"
HERCULES_READER_PORT="${HOST65_HERCULES_READER_PORT:-16065}"
HERCULES_SCREEN="host65-hercules"
FRONTDOOR_SCREEN="host65-frontdoor"
TSO_READY="$RUNTIME/TSO_READY"
FORTRAN_READY="$RUNTIME/FORTRAN_READY"
MVT_BASE_READY="$RUNTIME/MVT_BASE_READY"
MVT_FIRST_IPL_DONE="$RUNTIME/MVT_FIRST_IPL_DONE"
MVT_CONFIG="$MVT/mvt-host65.cnf"

usage() {
    cat <<USAGE
Usage: $(basename "$0") <prepare|reset-runtime|start|stop|restart|status|boot-mvt|verify-base-mvt|verify-frontdoor|verify-tso|verify-public-tso|verify-tso-fortran|verify-card-reader|verify|console|frontdoor>

Runs the UCLA-CCN host #65 support stack.

This is an OS/360 MVT/TSO implementation path for the UCLA-CCN scenario, not
recovered UCLA 360/91 media. TSO is not public-ready until verify sees a real
validation marker produced from an operator-tested Hercules/MVT/TSO session.
USAGE
}

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

have_screen() {
    screen -ls | grep -q "[.]$1[[:space:]]"
}

require_tools() {
    command -v curl >/dev/null || fail "curl is required"
    command -v unzip >/dev/null || fail "unzip is required"
    command -v hercules >/dev/null || fail "hercules is required"
    command -v screen >/dev/null || fail "screen is required"
    command -v nc >/dev/null || fail "nc is required"
    command -v timeout >/dev/null || fail "timeout is required"
    command -v s3270 >/dev/null || fail "s3270 is required for backend MVT/TSO validation"
}

prepare() {
    require_tools
    mkdir -p "$ROOT/kit-cache" "$RUNTIME" "$LOGS" "$TRANSCRIPTS"
    if [[ ! -f "$ARCHIVE" ]]; then
        echo "host65-ucla-ccn: downloading public OS/360 turnkey MVT package"
        curl -L --fail -o "$ARCHIVE" "$ARCHIVE_URL"
    fi
    if [[ ! -f "$MVT/mvt.cnf" ]]; then
        echo "host65-ucla-ccn: extracting OS/360 turnkey MVT package"
        rm -rf "$RUNTIME"
        mkdir -p "$RUNTIME"
        unzip -q "$ARCHIVE" -d "$RUNTIME"
    fi
    [[ -f "$MVT/mvt.cnf" ]] || fail "MVT configuration missing after prepare"
    chmod -R u+rwX "$RUNTIME"
    if [[ ! -f "$MVT_CONFIG" ]] || ! grep -q "CNSLPORT  $HERCULES_CONSOLE_PORT" "$MVT_CONFIG" || ! grep -q '^MAINSIZE  8$' "$MVT_CONFIG" || ! grep -Eq '^001F[[:space:]]+3215-C[[:space:]]+/' "$MVT_CONFIG" || ! grep -Eq "^000C[[:space:]]+2501[[:space:]]+[*][[:space:]]+intrq" "$MVT_CONFIG"; then
        sed \
            -e "s/^MAINSIZE  .*/MAINSIZE  8/" \
            -e "s/^CNSLPORT  .*/CNSLPORT  $HERCULES_CONSOLE_PORT/" \
            -e "s/^HTTPPORT  .*/HTTPPORT  $HERCULES_HTTP_PORT noauth/" \
            -e "s/^000C[[:space:]]\\+2501.*/000C    2501    * intrq/" \
            -e "s/^001F[[:space:]]\\+3215.*/001F    3215-C  \\/ noprompt/" \
            "$MVT/mvt.cnf" > "$MVT_CONFIG"
    fi
}

reset_runtime() {
    stop
    mkdir -p "$ROOT/kit-cache"
    [[ -f "$ARCHIVE" ]] || fail "archive missing; run prepare first: $ARCHIVE"
    echo "host65-ucla-ccn: resetting ignored runtime from cached archive"
    rm -rf "$RUNTIME" "$LOGS" "$TRANSCRIPTS"
    mkdir -p "$RUNTIME" "$LOGS" "$TRANSCRIPTS"
    unzip -q "$ARCHIVE" -d "$RUNTIME"
    prepare
}

start_hercules() {
    prepare
    if have_screen "$HERCULES_SCREEN"; then
        echo "host65-ucla-ccn: Hercules screen already present"
        return
    fi
    echo "host65-ucla-ccn: starting Hercules MVT backend"
    (cd "$MVT" && screen -dmS "$HERCULES_SCREEN" hercules -f "$(basename "$MVT_CONFIG")")
    sleep 2
}

start_frontdoor() {
    prepare
    if have_screen "$FRONTDOOR_SCREEN"; then
        echo "host65-ucla-ccn: front-door screen already present"
        return
    fi
    if ss -H -ltn 2>/dev/null | grep -q ":$FRONTDOOR_PORT "; then
        fail "TCP port $FRONTDOOR_PORT is already in use"
    fi
    echo "host65-ucla-ccn: starting line-mode CCN front door on $FRONTDOOR_PORT"
    screen -dmS "$FRONTDOOR_SCREEN" "$ROOT/ccn_frontdoor.py" \
        --port "$FRONTDOOR_PORT" \
        --ready-marker "$TSO_READY" \
        --hercules-port "$HERCULES_CONSOLE_PORT" \
        --transcript-dir "$TRANSCRIPTS"
    sleep 1
}

start() {
    if [[ ! -f "$TSO_READY" ]] || ! have_screen "$HERCULES_SCREEN"; then
        verify_tso
    fi
    start_frontdoor
    status
}

stop() {
    echo "host65-ucla-ccn: stopping"
    screen -S "$FRONTDOOR_SCREEN" -X quit 2>/dev/null || true
    screen -S "$HERCULES_SCREEN" -X stuff $'quit\n' 2>/dev/null || true
    sleep 1
    screen -S "$HERCULES_SCREEN" -X quit 2>/dev/null || true
    pkill -TERM -f 'hercules -f mvt-host65[.]cnf' 2>/dev/null || true
    pkill -TERM -f 'ccn_frontdoor[.]py' 2>/dev/null || true
    pkill -TERM -f "s3270 .*127[.]0[.]0[.]1:$HERCULES_CONSOLE_PORT" 2>/dev/null || true
    sleep 1
    pkill -KILL -f 'hercules -f mvt-host65[.]cnf' 2>/dev/null || true
    pkill -KILL -f 'ccn_frontdoor[.]py' 2>/dev/null || true
    pkill -KILL -f "s3270 .*127[.]0[.]0[.]1:$HERCULES_CONSOLE_PORT" 2>/dev/null || true
    echo "host65-ucla-ccn: stopped"
}

status() {
    if have_screen "$HERCULES_SCREEN"; then
        echo "host65-ucla-ccn: Hercules screen present"
    else
        echo "host65-ucla-ccn: Hercules screen absent"
    fi
    if have_screen "$FRONTDOOR_SCREEN"; then
        echo "host65-ucla-ccn: front-door screen present"
    else
        echo "host65-ucla-ccn: front-door screen absent"
    fi
    ps -eo pid,ppid,pgid,sid,stat,args | grep '[h]ercules -f mvt-host65[.]cnf' || true
    ps -eo pid,ppid,pgid,sid,stat,args | grep '[c]cn_frontdoor[.]py' || true
    ss -H -ltnp 2>/dev/null | grep -E ":($FRONTDOOR_PORT|$HERCULES_CONSOLE_PORT|$HERCULES_HTTP_PORT|$HERCULES_READER_PORT) " || true
    if [[ -f "$TSO_READY" ]]; then
        echo "host65-ucla-ccn: TSO validation marker present"
    else
        echo "host65-ucla-ccn: TSO validation marker absent"
    fi
    if [[ -f "$FORTRAN_READY" ]]; then
        echo "host65-ucla-ccn: FORTRAN validation marker present"
    else
        echo "host65-ucla-ccn: FORTRAN validation marker absent"
    fi
    if [[ -f "$MVT_BASE_READY" ]]; then
        echo "host65-ucla-ccn: base MVT validation marker present"
    else
        echo "host65-ucla-ccn: base MVT validation marker absent"
    fi
}

verify_frontdoor() {
    local transcript
    transcript="$({ printf 'HELP\rBBOARD\rLOGOFF\r'; sleep 1; } | timeout 5 nc 127.0.0.1 "$FRONTDOOR_PORT" 2>&1 | tr -d '\000' || true)"
    printf '%s\n' "$transcript" > "$TRANSCRIPTS/frontdoor-verify.txt"
    grep -q 'UCLA CCN 360/91 SERVER TELNET' <<<"$transcript" || fail "front-door banner not seen"
    grep -q 'TSO ACCESS TO IBM TSO TIME SHARING SYSTEM' <<<"$transcript" || fail "front-door HELP text not seen"
    grep -q 'UCLA CCN BULLETIN BOARD' <<<"$transcript" || fail "front-door BBOARD text not seen"
    echo "host65-ucla-ccn: front-door verified"
}

verify_public_tso() {
    prepare
    if [[ ! -f "$TSO_READY" ]] || ! have_screen "$HERCULES_SCREEN"; then
        verify_tso
    fi
    start_frontdoor
    local transcript
    transcript="$({
        printf 'TSO\r'
        sleep 5
        printf 'LOGON IBMUSER\r'
        sleep 8
        printf 'TIME\r'
        sleep 5
        printf 'LOGOFF\r'
        sleep 4
    } | timeout 40 nc -N 127.0.0.1 "$FRONTDOOR_PORT" 2>&1 | tr -d '\000' || true)"
    printf '%s\n' "$transcript" > "$TRANSCRIPTS/public-tso-verify.txt"
    grep -q 'CONNECTING TO UCLA-CCN OS/360 MVT TSO' <<<"$transcript" || fail "public TSO bridge did not start"
    grep -q 'IKJ54012A ENTER LOGON' <<<"$transcript" || fail "public TSO prompt not seen"
    grep -q 'LOGON IBMUSER' <<<"$transcript" || fail "public TSO login command not echoed"
    grep -Eq '(^|[[:space:]])READY([[:space:]]|$)' <<<"$transcript" || fail "public TSO READY prompt not seen"
    grep -q 'CPU -' <<<"$transcript" || fail "public TSO TIME output not seen"
    grep -q 'LOGGED OFF TSO' <<<"$transcript" || fail "public TSO LOGOFF output not seen"
    echo "host65-ucla-ccn: public TSO bridge verified"
}

verify_tso_fortran() {
    prepare
    if [[ ! -f "$TSO_READY" ]] || ! have_screen "$HERCULES_SCREEN"; then
        verify_tso
    fi
    start_frontdoor
    rm -f "$FORTRAN_READY"

    local transcript
    transcript="$({
        printf 'TSO\r'
        sleep 5
        printf 'LOGON IBMUSER\r'
        sleep 10
        printf 'DELETE H.FORT\r'
        sleep 4
        printf 'DELETE H.OBJ\r'
        sleep 4
        printf 'EDIT H NEW FORTG\r'
        sleep 6
        printf '      WRITE(6,10)\r'
        sleep 1
        printf '   10 FORMAT(1X,10HHELLO FORT)\r'
        sleep 1
        printf '      END\r'
        sleep 1
        printf '\r'
        sleep 4
        printf 'SAVE\r'
        sleep 4
        printf 'END\r'
        sleep 6
        printf 'ALLOC FILE(SYSIN) DATASET(H.FORT) SHR\r'
        sleep 8
        printf '\r'
        sleep 4
        printf 'ALLOC FILE(SYSLIN) DATASET(H.OBJ) NEW BLOCK(80) SPACE(10,5)\r'
        sleep 10
        printf '\r'
        sleep 4
        printf 'ALLOC FILE(SYSPRINT) DATASET(*)\r'
        sleep 8
        printf '\r'
        sleep 4
        printf '%s\r' "CALL 'SYS1.LINKLIB(IEYFORT)'"
        sleep 55
        printf 'ALLOC FILE(FT06F001) DATASET(*)\r'
        sleep 8
        printf '\r'
        sleep 4
        printf 'LOADGO H FORTLIB PRINT(*)\r'
        sleep 55
        printf 'LISTCAT\r'
        sleep 6
        printf 'LOGOFF\r'
        sleep 5
    } | timeout 260 nc -N 127.0.0.1 "$FRONTDOOR_PORT" 2>&1 | tr -d '\000' || true)"

    printf '%s\n' "$transcript" > "$TRANSCRIPTS/tso-fortran-verify.txt"
    grep -q 'CONNECTING TO UCLA-CCN OS/360 MVT TSO' <<<"$transcript" || fail "public TSO bridge did not start"
    grep -q 'IKJ54012A ENTER LOGON' <<<"$transcript" || fail "TSO logon prompt not seen"
    grep -Eq '(^|[[:space:]])READY([[:space:]]|$)' <<<"$transcript" || fail "TSO READY prompt not seen"
    grep -Eq 'INPUT|EDIT' <<<"$transcript" || fail "TSO EDIT did not enter source input/edit mode"
    grep -q 'SAVED' <<<"$transcript" || fail "TSO EDIT source was not saved"
    grep -q 'CALL .SYS1[.]LINKLIB(IEYFORT).' <<<"$transcript" || fail "real FORTRAN compiler CALL was not seen"
    grep -q 'FORTRAN IV G LEVEL' <<<"$transcript" || fail "real FORTRAN IV G compiler output was not seen"
    grep -q 'NO DIAGNOSTICS GENERATED' <<<"$transcript" || fail "FORTRAN compile did not complete cleanly"
    grep -q 'LOADGO H FORTLIB PRINT' <<<"$transcript" || fail "real LOADGO command was not seen"
    grep -q 'OS/360 LOADER' <<<"$transcript" || fail "OS/360 loader output was not seen"
    grep -q 'HELLO FORT' <<<"$transcript" || fail "FORTRAN program output was not seen"
    grep -q 'H.FORT' <<<"$transcript" || fail "LISTCAT did not show the test source data set"
    grep -q 'LOGGED OFF TSO' <<<"$transcript" || fail "TSO LOGOFF output not seen"
    if grep -Eq 'COMMAND [A-Z0-9]+[[:space:]]+NOT FOUND|INVALID COMMAND SYNTAX|COMPLETION CODE - SYSTEM=[1-9A-F]|ABEND|JCL ERROR|STEP WAS NOT EXECUTED|LOAD MODULE DOES NOT EXIST|IKJ56452I|COMMAND SYSTEM ERROR|IEY035I UNABLE TO OPEN|IKJ54020A MESSAGE LOST' <<<"$transcript"; then
        fail "interactive TSO/FORTRAN validation produced an error; see $TRANSCRIPTS/tso-fortran-verify.txt"
    fi
    touch "$FORTRAN_READY"
    echo "host65-ucla-ccn: interactive TSO FORTRAN verified"
}

hercules_panel_cmd() {
    have_screen "$HERCULES_SCREEN" || fail "Hercules screen is not running"
    screen -S "$HERCULES_SCREEN" -X stuff "$1"$'\n'
}

operator_cmd() {
    # 001F is generated as a Hercules integrated 3215-C alternate console.
    # The slash is the configured console command prefix, not an OS command.
    hercules_panel_cmd "/$1"
}

wait_for_printer_text() {
    local pattern="$1"
    local timeout_s="${2:-120}"
    local start
    start="$(date +%s)"
    while (( "$(date +%s)" - start < timeout_s )); do
        capture_backend
        if grep -Eq "$pattern" "$LOGS/prt00e.txt" 2>/dev/null; then
            return 0
        fi
        sleep 2
    done
    return 1
}

verify_card_reader() {
    prepare
    if [[ ! -f "$TSO_READY" ]] || ! have_screen "$HERCULES_SCREEN"; then
        verify_tso
    fi
    local smoke_deck="$MVT/sample/iebgener.jcl"
    local deck="$MVT/sample/forthclg.jcl"
    [[ -f "$smoke_deck" ]] || fail "card-reader smoke deck missing: $smoke_deck"
    [[ -f "$deck" ]] || fail "FORTRAN sample deck missing: $deck"

    mkdir -p "$LOGS" "$TRANSCRIPTS"
    cp "$MVT/prt00e.txt" "$TRANSCRIPTS/prt00e-before-fortran.txt" 2>/dev/null || true

    echo "host65-ucla-ccn: submitting real OS/360 IEBGENER card deck"
    hercules_panel_cmd "devinit 00c sample/iebgener.jcl eof"
    sleep 1
    hercules_panel_cmd "i 00c"
    wait_for_printer_text 'IEBGENER|FORTHCLG|ASMFCL' 180 \
        || fail "IEBGENER card-reader smoke deck did not print; see $LOGS/mvtlog.txt and $LOGS/prt00e.txt"

    echo "host65-ucla-ccn: submitting real OS/360 FORTRAN IV G card deck"
    hercules_panel_cmd "devinit 00c sample/forthclg.jcl eof"
    sleep 1
    hercules_panel_cmd "i 00c"

    if ! wait_for_printer_text 'HELLO[[:space:]]+WORLD|FORTHCLG|FORTRAN' 240; then
        capture_backend
        fail "FORTRAN batch output did not reach printer; see $LOGS/mvtlog.txt and $LOGS/prt00e.txt"
    fi
    if grep -Eq 'COMPLETION CODE - SYSTEM=[1-9A-F]|ABEND|JCL ERROR|STEP WAS NOT EXECUTED|LOAD MODULE DOES NOT EXIST' "$LOGS/prt00e.txt" "$LOGS/mvtlog.txt" 2>/dev/null; then
        fail "FORTRAN batch produced an error; see $LOGS/prt00e.txt and $LOGS/mvtlog.txt"
    fi
    grep -Eq 'HELLO[[:space:]]+WORLD' "$LOGS/prt00e.txt" \
        || fail "FORTRAN deck ran but HELLO WORLD output was not found; see $LOGS/prt00e.txt"
    cp "$LOGS/prt00e.txt" "$TRANSCRIPTS/fortran-batch-printer.txt"
    echo "host65-ucla-ccn: card-reader batch path verified"
}

verify_fortran_batch() {
    verify_card_reader
}

capture_backend() {
    screen -S "$HERCULES_SCREEN" -X hardcopy -h "$LOGS/hercules-screen.txt" 2>/dev/null || true
    cp "$MVT/mvtlog.txt" "$LOGS/mvtlog.txt" 2>/dev/null || true
    cp "$MVT/prt00e.txt" "$LOGS/prt00e.txt" 2>/dev/null || true
}

console_boot_stream() {
    local first_ipl="$1"
    local include_tso="${2:-0}"
    printf 'Connect(127.0.0.1:%s)\n' "$HERCULES_CONSOLE_PORT"
    sleep 7
    printf 'Ascii()\n'
    printf 'Enter()\n'
    sleep 6
    printf 'Ascii()\n'
    printf "String(\"r 00,'no'\")\nEnter()\n"
    sleep 8
    printf 'Ascii()\n'
    if (( first_ipl )); then
        printf 'String("r 00,q=(,f)")\nEnter()\n'
        sleep 10
        printf 'Ascii()\n'
        printf 'String("r 01,u")\nEnter()\n'
    else
        printf 'String("r 00,u")\nEnter()\n'
    fi
    sleep 12
    printf 'Ascii()\n'
    printf 'String("mn jobnames,t")\nEnter()\n'
    sleep 2
    printf 'String("mn status")\nEnter()\n'
    sleep 2
    printf 'String("s init")\nEnter()\n'
    sleep 8
    printf 'Ascii()\n'
    printf 'String("d a")\nEnter()\n'
    sleep 4
    printf 'Ascii()\n'
    printf 'String("s wtr,00e")\nEnter()\n'
    sleep 5
    printf 'Ascii()\n'
    printf 'String("r 01,pn")\nEnter()\n'
    sleep 3
    printf 'String("s rdr,00c")\nEnter()\n'
    sleep 8
    printf 'String("d a")\nEnter()\n'
    sleep 5
    printf 'Ascii()\n'
    if (( include_tso )); then
        printf 'String("s tcam")\nEnter()\n'
        sleep 12
        printf 'Ascii()\n'
        printf 'String("s tso")\nEnter()\n'
        sleep 30
        printf 'String("d a")\nEnter()\n'
        sleep 8
        printf 'Ascii()\n'
        # Keep console 00C0 attached so a second s3270 can take TCAM terminal 00C1.
        sleep 90
    fi
    printf 'Quit()\n'
}

boot_mvt() {
    prepare
    rm -f "$MVT_BASE_READY" "$TSO_READY"
    start_hercules
    mkdir -p "$LOGS" "$TRANSCRIPTS"

    local transcript="$TRANSCRIPTS/mvt-boot.txt"
    local first_ipl=0
    if [[ ! -f "$MVT_FIRST_IPL_DONE" ]]; then
        first_ipl=1
    fi

    (
        sleep 2
        screen -S "$HERCULES_SCREEN" -X stuff $'ipl 350\n'
    ) &

    echo "host65-ucla-ccn: booting MVT via backend 3270 console"
    if ! console_boot_stream "$first_ipl" 0 | timeout 150 s3270 -script > "$transcript" 2>&1; then
        capture_backend
        fail "s3270 MVT boot script failed; see $transcript"
    fi
    touch "$MVT_FIRST_IPL_DONE"
    capture_backend
    verify_base_mvt
}

verify_base_mvt() {
    mkdir -p "$LOGS" "$TRANSCRIPTS"
    capture_backend
    local combined="$TRANSCRIPTS/base-mvt-verify.txt"
    {
        printf '%s\n' '--- mvt boot transcript ---'
        sed -n '1,240p' "$TRANSCRIPTS/mvt-boot.txt" 2>/dev/null || true
        printf '%s\n' '--- mvtlog ---'
        sed -n '1,260p' "$LOGS/mvtlog.txt" 2>/dev/null || true
        printf '%s\n' '--- printer ---'
        sed -n '1,260p' "$LOGS/prt00e.txt" 2>/dev/null || true
    } > "$combined"

    if grep -q 'COMPLETION CODE - SYSTEM=2F3' "$combined"; then
        fail "base MVT started task hit S2F3; see $combined"
    fi
    grep -Eq "IEF429I INITIATOR '?INIT'? WAITING FOR WORK|INIT[[:space:]]+WAITING FOR WORK|NAME1[[:space:]]+NAME2[[:space:]]+NAME3" "$combined" \
        || fail "INIT waiting/active state not verified; see $combined"
    grep -Eq "WTR[[:space:]]+WAITING FOR WORK|WTR[[:space:]]+00E|IEF403I WTR" "$combined" \
        || fail "WTR waiting/active state not verified; see $combined"
    grep -Eq "RDR[[:space:]]+00C|IEF403I RDR|00C,INT REQ" "$combined" \
        || fail "RDR active or expected card-reader intervention not verified; see $combined"

    touch "$MVT_BASE_READY"
    echo "host65-ucla-ccn: base MVT verified"
}

verify_tso() {
    prepare
    reset_runtime
    rm -f "$MVT_BASE_READY" "$TSO_READY"
    start_hercules
    mkdir -p "$LOGS" "$TRANSCRIPTS"

    local console_transcript="$TRANSCRIPTS/tso-console.txt"
    local user_transcript="$TRANSCRIPTS/tso-login.txt"
    local console_fifo="$RUNTIME/tso-console.fifo"

    (
        sleep 2
        screen -S "$HERCULES_SCREEN" -X stuff $'ipl 350\n'
    ) &

    echo "host65-ucla-ccn: booting MVT and starting TCAM/TSO via live 3270 console"
    rm -f "$console_fifo"
    mkfifo "$console_fifo"
    timeout 520 s3270 -script < "$console_fifo" > "$console_transcript" 2>&1 &
    local console_pid=$!
    exec 9> "$console_fifo"

    send_console() {
        printf '%s\n' "$*" >&9
    }

    send_console "Connect(127.0.0.1:$HERCULES_CONSOLE_PORT)"
    sleep 7
    send_console 'Ascii()'
    send_console 'Enter()'
    sleep 6
    send_console 'Ascii()'
    send_console "String(\"r 00,'no'\")"
    send_console 'Enter()'
    sleep 8
    send_console 'Ascii()'
    send_console 'String("r 00,q=(,f)")'
    send_console 'Enter()'
    sleep 10
    send_console 'Ascii()'
    send_console 'String("r 01,u")'
    send_console 'Enter()'
    sleep 12
    send_console 'Ascii()'
    send_console 'String("mn jobnames,t")'
    send_console 'Enter()'
    sleep 2
    send_console 'String("mn status")'
    send_console 'Enter()'
    sleep 2
    send_console 'String("s init")'
    send_console 'Enter()'
    sleep 8
    send_console 'Ascii()'
    send_console 'String("d a")'
    send_console 'Enter()'
    sleep 4
    send_console 'Ascii()'
    send_console 'String("s wtr,00e")'
    send_console 'Enter()'
    sleep 5
    send_console 'Ascii()'
    send_console 'String("r 01,pn")'
    send_console 'Enter()'
    sleep 3

    send_console 'String("s rdr,00c")'
    send_console 'Enter()'
    sleep 8
    send_console 'String("d a")'
    send_console 'Enter()'
    sleep 5
    send_console 'Ascii()'

    send_console 'String("s tcam")'
    send_console 'Enter()'
    sleep 12
    send_console 'Ascii()'
    send_console 'String("s tso")'
    send_console 'Enter()'
    sleep 30
    send_console 'String("d a")'
    send_console 'Enter()'
    sleep 8
    send_console 'Ascii()'

    sleep 5

    echo "host65-ucla-ccn: attempting IBMUSER TSO login on TCAM terminal"
    {
        printf 'Connect(127.0.0.1:%s)\n' "$HERCULES_CONSOLE_PORT"
        sleep 5
        printf 'Clear()\n'
        sleep 5
        printf 'Ascii()\n'
        printf 'Home()\n'
        printf 'String("LOGON IBMUSER")\n'
        printf 'EraseEOF()\n'
        printf 'Enter()\n'
        sleep 18
        printf 'Ascii()\n'
        printf 'Home()\n'
        printf 'String("LOGOFF")\n'
        printf 'EraseEOF()\n'
        printf 'Enter()\n'
        sleep 8
        printf 'Ascii()\n'
        printf 'Quit()\n'
    } | timeout 80 s3270 -script > "$user_transcript" 2>&1 || true

    sleep 10
    send_console 'Quit()'
    exec 9>&-
    rm -f "$console_fifo"

    wait "$console_pid" || {
        capture_backend
        fail "console TCAM/TSO startup script failed; see $console_transcript"
    }

    touch "$MVT_FIRST_IPL_DONE"
    capture_backend

    if grep -q 'COMPLETION CODE - SYSTEM=2F3' "$console_transcript" "$LOGS/mvtlog.txt" "$LOGS/prt00e.txt" 2>/dev/null; then
        fail "TCAM/TSO startup hit S2F3; see $console_transcript and $LOGS"
    fi
    grep -Eq 'IEF403I TCAM|TCAM[[:space:]]+STARTED|TCAM[[:space:]]+TCAM' "$console_transcript" "$LOGS/mvtlog.txt" "$LOGS/prt00e.txt" 2>/dev/null \
        || fail "TCAM start not verified; see $console_transcript"
    grep -Eq 'IKJ019I TSO HAS BEEN INITIALIZED|IEF403I TSO|TSO[[:space:]]+STARTED|TSO[[:space:]]+TSO' "$console_transcript" "$LOGS/mvtlog.txt" "$LOGS/prt00e.txt" 2>/dev/null \
        || fail "TSO initialization not verified; see $console_transcript"
    grep -q 'IKJ54012A ENTER LOGON' "$user_transcript" \
        || fail "TSO logon prompt not seen; see $user_transcript"
    if grep -q 'IKJ56452I LOGON TERMINATED. SYSTEM ERROR' "$user_transcript"; then
        fail "IBMUSER logon reached TSO but terminated with system error; see $user_transcript"
    fi
    grep -q 'IBMUSER LOGON IN PROGRESS' "$user_transcript" \
        || fail "IBMUSER logon progress message not seen; see $user_transcript"
    grep -Eq '(^|data:[[:space:]]+)READY[[:space:]]*$' "$user_transcript" \
        || fail "IBMUSER READY prompt not seen; see $user_transcript"
    grep -q 'LOGGED OFF TSO' "$user_transcript" \
        || fail "IBMUSER validation did not log off cleanly; see $user_transcript"

    touch "$MVT_BASE_READY" "$TSO_READY"
    echo "host65-ucla-ccn: TSO validated"
}

verify() {
    prepare
    start_frontdoor
    verify_frontdoor
    if [[ ! -f "$TSO_READY" ]] || ! have_screen "$HERCULES_SCREEN"; then
        verify_tso
    fi
    echo "host65-ucla-ccn: TSO validation marker present"
    verify_public_tso
    verify_tso_fortran
}

console() {
    have_screen "$HERCULES_SCREEN" || fail "Hercules screen is not running"
    screen -r "$HERCULES_SCREEN"
}

frontdoor() {
    have_screen "$FRONTDOOR_SCREEN" || fail "front-door screen is not running"
    screen -r "$FRONTDOOR_SCREEN"
}

case "$ACTION" in
    prepare) prepare ;;
    reset-runtime) reset_runtime ;;
    start) start ;;
    stop) stop ;;
    restart) stop; start ;;
    status) status ;;
    boot-mvt) boot_mvt ;;
    verify-base-mvt) verify_base_mvt ;;
    verify-frontdoor) prepare; start_frontdoor; verify_frontdoor ;;
    verify-public-tso) verify_public_tso ;;
    verify-tso-fortran) verify_tso_fortran ;;
    verify-card-reader) verify_card_reader ;;
    verify-fortran-batch) verify_fortran_batch ;;
    verify-tso) verify_tso ;;
    verify) verify ;;
    console) console ;;
    frontdoor) frontdoor ;;
    *) usage; exit 1 ;;
esac
