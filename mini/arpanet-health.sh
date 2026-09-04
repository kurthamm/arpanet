#!/usr/bin/env bash
# arpanet-health.sh -- the ONE reliable "what is actually up" tool.
#
# Why this exists: `ncp-ping` and `systemctl is-active` both LIE.
#   - ncp-ping replies from the IMP/ncpdov even when the guest OS behind it is dead
#     or refusing logins (host 11 looked "up" via ping while its KA was gone).
#   - a Type=oneshot host unit shows `active` forever after boot even if the guest's
#     screen later died (oneshot doesn't track the screen).
# The only ground truth for "a visitor can actually use this host" is the real @L
# login path (do.sh -> ncp-telnet through the IMPs). This tool runs that, AND probes
# each underlying layer, so when a host is down you see WHICH layer failed instead
# of guessing.
#
# Usage:
#   arpanet-health.sh                 full table (layer probes + live @L truth)
#   arpanet-health.sh --fast          layer probes only (no @L; instant, zero mesh traffic)
#   arpanet-health.sh <host>          deep single-host diagnosis (verbose, layer by layer)
#   arpanet-health.sh --diagnose <h>  same as above
#
# Read-only. The @L probe opens one short session per host, serially (never the
# rapid ncp-telnet spam that perturbs mesh routing).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
DOSH="$ROOT/do.sh"

# Host model.  Fields (":"-separated):
#   num : name : type : session : banner_regex : imp : imp_port : host_port : line_port : ncp_sock : fep_screen
# type = its | tenex | waits | fep.  "-" = not applicable.
# banner_regex is what a healthy @L prints; session is do.sh SESSION_NUMBER (ITS use
# a TIP source, FEP/others use 0).
HOSTS=(
  "69:BBN-TENEX:tenex:5:Tenex|EXEC|@:-:-:-:-:-:-"
  "70:MIT-DMS:its:5:Dynamic Modelling|turist:6:21061:21062:17015:-:-"
  "126:HILTON-KA1:its:5:ITS PDP-10|turist:62:21621:21622:10015:-:-"
  "134:MIT-AI:its:5:Artificial Intelligence|turist:6:22061:22062:18015:-:-"
  "198:MIT-ML:its:5:Math Lab|turist:6:23061:23062:19015:-:-"
  "11:SU-AI-WAITS:waits:5:WAITS|login|PLEASE LOG:11:20111:20112:1025:ncp11:fep11"
  "6:MIT-MULTICS:fep:0:HSLA|Multics|MR12:6:-:-:6180:ncp06:fep6"
  "1:UCLA-Sigma:fep:0:Sigma|MUX:-:-:-:4003:ncp01:fep1"
  "65:UCLA-CCN-OS360:fep:0:CCN|360/91:-:-:-:16515:ncp65:fep65"
)

# --- low-level, non-perturbing probes ---
sock_bound()  { ss -Huna 2>/dev/null | grep -qE "127\.0\.0\.1:$1\b"; }         # udp socket present
line_listen() { ss -Hltn 2>/dev/null | grep -qE "[:.]$1\b"; }                  # tcp line port listening
screen_up()   { screen -ls 2>/dev/null | grep -qE "[.]$1[[:space:]]"; }
imp_running() { [ "$1" = "-" ] && return 0; "$HERE/impctl.py" status "$1" 2>/dev/null | grep -q 'State:[[:space:]]*RUNNING'; }
its_ka_up()   { pgrep -f "pdp10-ka-fixed ./mini-run" 2>/dev/null | while read -r p; do
                  [ "$(readlink /proc/$p/cwd 2>/dev/null)" = "$ROOT/mini/host$1" ] && { echo up; return; }; done | grep -q up; }

# @L truth probe: returns "BANNER" / "OPEN" / "REFUSED" and echoes the captured line on fd 3.
# TENEX serves login on NCP socket 1 (ncp-telnet -o 69), not the default @L path, so
# probe it directly; every other host answers the generic @L visitor path via do.sh.
atl_probe() {
  local num="$1" sess="$2" rex="$3" type="$4" out line
  if [ "$type" = tenex ]; then
    out="$( (sleep 2; printf '\r'; sleep 6) | timeout 25 env NCP=ncp31 "$HERE/ncp-telnet" -o "$num" 2>&1 | tr -d '\r' )"
  else
    out="$( (printf '@L %s\r\n' "$num"; sleep 6) | SESSION_NUMBER="$sess" timeout 25 "$DOSH" 2>&1 | tr -d '\r' )"
  fi
  line="$(printf '%s' "$out" | sed 's/\[NOECHO\]//g' | grep -ivE '^\s*$|TELNET to host' | head -1 | cut -c1-46)"
  printf '%s\n' "${line:-}" >&3
  if printf '%s' "$out" | grep -qiE "$rex"; then echo BANNER
  elif printf '%s' "$out" | grep -qiE 'open refused|cannot be reached|not up|host down'; then echo REFUSED
  elif [ -n "$line" ]; then echo OPEN
  else echo REFUSED; fi
}

# Diagnose one host -> sets STATUS ("UP"/"DOWN"/"DEGRADED") and DIAG (why).
diagnose() {
  local num="$1" name="$2" type="$3" sess="$4" rex="$5" imp="$6" ipx="$7" hpx="$8" lpx="$9" ncp="${10}" fep="${11}"
  local verbose="${12:-0}" atl banner
  STATUS=DOWN; DIAG=""

  # layer probes
  local os_up=1 link_up=1 impside=1 imp_up=1 fep_up=1 ncp_up=1
  case "$type" in
    tenex) pgrep -f "pdp10-ki .*run-h69" >/dev/null 2>&1 || os_up=0 ;;
    its)   its_ka_up "$num" || os_up=0
           sock_bound "$hpx" || link_up=0
           sock_bound "$ipx" || impside=0
           imp_running "$imp" || imp_up=0 ;;
    waits) screen_up "host$num" || os_up=0
           line_listen "$lpx" || os_up=0
           [ "$fep" = "-" ] || screen_up "$fep" || fep_up=0 ;;
    fep)   line_listen "$lpx" || os_up=0
           [ -S "$HERE/$ncp" ] || ncp_up=0
           screen_up "$fep" || fep_up=0 ;;
  esac

  # ground truth (skipped in --fast mode; then verdict is layer-only)
  if [ "${SKIP_ATL:-0}" = 1 ]; then
    atl=SKIP; banner=""
  else
    atl="$(atl_probe "$num" "$sess" "$rex" "$type" 3>/tmp/health-atl.$$)"; banner="$(cat /tmp/health-atl.$$ 2>/dev/null)"; rm -f /tmp/health-atl.$$
  fi

  # classify: @L is the truth; layers explain a non-UP.
  if [ "$atl" = SKIP ]; then
    # layer-only verdict: LAYERS_OK if every applicable layer probe is green
    if [ "$os_up$link_up$impside$imp_up$fep_up$ncp_up" = "111111" ]; then
      STATUS=LAYERS_OK; DIAG="all layers up (@L not probed; run without --fast to confirm)"
    fi
  fi
  if [ "$atl" = BANNER ] || { [ "$type" = waits ] && [ "$atl" = OPEN ]; }; then
    STATUS=UP; DIAG="@L serves${banner:+: $banner}"
  elif [ "$atl" = SKIP ] && [ "$STATUS" = LAYERS_OK ]; then
    :  # keep LAYERS_OK diag set above
  else
    case "$type" in
      tenex) [ "$os_up" = 0 ] && DIAG="TENEX KA (pdp10-ki) not running" || DIAG="@L refused though KA is up (still booting / login server down)";;
      its)   if   [ "$os_up"  = 0 ]; then DIAG="guest OS not running (no host$num KA screen)"
             elif [ "$imp_up" = 0 ]; then DIAG="IMP $imp not RUNNING"
             elif [ "$impside" = 0 ]; then DIAG="IMP $imp interface DETACHED (imp-side udp $ipx absent) -> arpanet-recover.sh reconcile"
             elif [ "$link_up" = 0 ]; then DIAG="host not attached to its IMP line (host-side udp $hpx absent) -> reboot host $num"
             else DIAG="link up but @L not answering (guest still booting, or NCP login not up)"; fi;;
      waits) if   [ "$os_up" = 0 ]; then DIAG="WAITS not running (no host$num KA / line $lpx down) -> host11ctl.sh start $num"
             elif [ "$fep_up" = 0 ]; then DIAG="FEP bridge $fep down -> fepctl.sh start $num"
             else DIAG="WAITS + bridge up but @L refused -> fepctl restart $num"; fi;;
      fep)   if   [ "$os_up" = 0 ]; then
               case "$num" in
                 1)  DIAG="deployed but sim not running (line $lpx down) -> host01-sigma/host01-sigmactl.sh start";;
                 6)  DIAG="deployed but sim not running (line $lpx down) -> systemctl start arpanet-host06-multics";;
                 65) DIAG="deployed but sim not running (line $lpx down) -> host65-ucla-ccnctl.sh start";;
                 *)  DIAG="deployed but sim not running (line $lpx down)";;
               esac
             elif [ "$ncp_up" = 0 ]; then DIAG="NCP socket $ncp missing"
             elif [ "$fep_up" = 0 ]; then DIAG="FEP bridge $fep down -> fepctl.sh start $num"
             else DIAG="sim+bridge up but @L refused -> restart $fep / ncp daemon"; fi;;
    esac
    [ "$atl" = OPEN ] && STATUS=DEGRADED
  fi

  if [ "$verbose" = 1 ]; then
    printf '\nhost %s (%s, %s)\n' "$num" "$name" "$type"
    case "$type" in
      its)   printf '  guest KA screen host%s : %s\n' "$num" "$([ "$os_up" = 1 ] && echo up || echo DOWN)"
             printf '  host->IMP udp %s        : %s\n' "$hpx" "$([ "$link_up" = 1 ] && echo bound || echo ABSENT)"
             printf '  IMP %s->host udp %s     : %s\n' "$imp" "$ipx" "$([ "$impside" = 1 ] && echo bound || echo DETACHED)"
             printf '  IMP %s process          : %s\n' "$imp" "$([ "$imp_up" = 1 ] && echo RUNNING || echo down)";;
      tenex) printf '  TENEX KA (pdp10-ki)     : %s\n' "$([ "$os_up" = 1 ] && echo up || echo DOWN)";;
      waits) printf '  WAITS KA screen host%s  : %s\n' "$num" "$(screen_up "host$num" && echo up || echo DOWN)"
             printf '  sim line %s listening   : %s\n' "$lpx" "$(line_listen "$lpx" && echo yes || echo NO)"
             printf '  FEP bridge %s           : %s\n' "$fep" "$([ "$fep_up" = 1 ] && echo up || echo DOWN)";;
      fep)   printf '  sim line %s listening   : %s\n' "$lpx" "$([ "$os_up" = 1 ] && echo yes || echo NO)"
             printf '  NCP socket %s           : %s\n' "$ncp" "$([ "$ncp_up" = 1 ] && echo present || echo MISSING)"
             printf '  FEP bridge %s           : %s\n' "$fep" "$([ "$fep_up" = 1 ] && echo up || echo DOWN)";;
    esac
    printf '  @L login (visitor path) : %s%s\n' "$atl" "${banner:+  [$banner]}"
    printf '  VERDICT: %s -- %s\n' "$STATUS" "$DIAG"
  fi
}

# --- entry ---
FAST=0; TARGET=""
case "${1:-}" in
  --fast) FAST=1 ;;
  --diagnose) TARGET="${2:-}" ;;
  "" ) ;;
  * ) TARGET="$1" ;;
esac

if [ -n "$TARGET" ]; then
  for row in "${HOSTS[@]}"; do IFS=: read -r n rest <<<"$row"
    [ "$n" = "$TARGET" ] && { IFS=: read -r num name type sess rex imp ipx hpx lpx ncp fep <<<"$row"; diagnose "$num" "$name" "$type" "$sess" "$rex" "$imp" "$ipx" "$hpx" "$lpx" "$ncp" "$fep" 1; exit 0; }
  done
  echo "unknown host: $TARGET"; exit 2
fi

printf '%-5s %-16s %-6s %-10s %s\n' HOST NAME TYPE STATUS DIAGNOSIS
printf '%-5s %-16s %-6s %-10s %s\n' ----- ---------------- ------ ---------- ---------
up=0; down=0
for row in "${HOSTS[@]}"; do
  IFS=: read -r num name type sess rex imp ipx hpx lpx ncp fep <<<"$row"
  SKIP_ATL="$FAST" diagnose "$num" "$name" "$type" "$sess" "$rex" "$imp" "$ipx" "$hpx" "$lpx" "$ncp" "$fep" 0
  printf '%-5s %-16s %-6s %-10s %s\n' "$num" "$name" "$type" "$STATUS" "$DIAG"
  [ "$STATUS" = UP ] && up=$((up+1)) || down=$((down+1))
done
printf '\n%d up, %d not-up\n' "$up" "$down"
