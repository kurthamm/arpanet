#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/host69-bbn-tenex" && pwd)"
REPO="$(cd "$ROOT/../.." && pwd)"
SIM="${SIM:-$REPO/mini/host70/pdp10-ka}"
KIT="$ROOT/kit-cache/tenex"
BUILD_TENEX="$ROOT/kit-cache/build-tenex"
RCORNWELL="$ROOT/kit-cache/rcornwell-sims"
RCORNWELL_PATCH="$ROOT/patches/rcornwell-bbn-tenex.patch"
PDP10_KI="${PDP10_KI:-$RCORNWELL/BIN/pdp10-ki}"
RUNTIME="$ROOT/runtime"
LOGS="$ROOT/logs"
TRANSCRIPTS="$ROOT/transcripts"
TIMEOUT_SECS="${TIMEOUT_SECS:-10}"
BUILD_TENEX_TIMEOUT_SECS="${BUILD_TENEX_TIMEOUT_SECS:-600}"
BUILD_TENEX_BOOT_WAIT_SECS="${BUILD_TENEX_BOOT_WAIT_SECS:-120}"
HOST69_DC_PORT="${HOST69_DC_PORT:-16945}"
HOST69_TYM_PORT="${HOST69_TYM_PORT:-16946}"
HOST69_PORTS_RE='16945|16946|12345|12346|16969|10569'

TENEX_REPO_URL="${TENEX_REPO_URL:-https://github.com/PDP-10/tenex.git}"
BSYS_REPO_URL="${BSYS_REPO_URL:-https://github.com/PDP-10/bsys.git}"
IMSSS_REPO_URL="${IMSSS_REPO_URL:-https://github.com/PDP-10/imsss.git}"
BUILD_TENEX_REPO_URL="${BUILD_TENEX_REPO_URL:-https://github.com/larsbrinkhoff/build-tenex.git}"
RCORNWELL_REPO_URL="${RCORNWELL_REPO_URL:-https://github.com/rcornwell/sims.git}"

ARTIFACTS=(
  "133-tenex/eddt.10x"
  "133-tenex/lod10x.run"
  "133-tenex/tendmp.10x"
  "134-tenex/EDDT.10X"
  "134-tenex/LOD10X.RUN"
  "134-tenex/TENDMP.10X"
  "134-tenex/TENEX.SAV"
)

mkdirs() {
  mkdir -p "$KIT" "$RUNTIME" "$LOGS" "$TRANSCRIPTS"
}

has_re() {
  local pattern="$1"
  shift
  if command -v rg >/dev/null 2>&1; then
    rg -q "$pattern" "$@"
  else
    grep -Eq "$pattern" "$@"
  fi
}

has_fixed() {
  local pattern="$1"
  shift
  if command -v rg >/dev/null 2>&1; then
    rg -qF "$pattern" "$@"
  else
    grep -Fq "$pattern" "$@"
  fi
}

filter_re() {
  local pattern="$1"
  if command -v rg >/dev/null 2>&1; then
    rg "$pattern"
  else
    grep -E "$pattern"
  fi
}

require_sim() {
  if [[ ! -x "$SIM" ]]; then
    echo "SIMH PDP-10 binary not found or not executable: $SIM" >&2
    exit 1
  fi
}

prepare() {
  mkdirs
  require_sim

  if [[ -d "$KIT/.git" ]]; then
    echo "TENEX kit already present: $KIT"
  elif [[ -d /tmp/tenex-spike/.git ]]; then
    echo "Copying existing TENEX checkout from /tmp/tenex-spike"
    cp -a /tmp/tenex-spike/. "$KIT/"
  else
    echo "Cloning TENEX kit into ignored cache: $KIT"
    rm -rf "$KIT"
    git clone "$TENEX_REPO_URL" "$KIT"
  fi

  echo "Prepared BBN-TENEX lab under $ROOT"
}

clone_or_update() {
  local url="$1"
  local dir="$2"
  if [[ -d "$dir/.git" ]]; then
    local branch
    branch="$(git -C "$dir" symbolic-ref --short HEAD)"
    git -C "$dir" fetch origin "$branch" >/dev/null
    git -C "$dir" merge --ff-only "origin/$branch" >/dev/null
  else
    git clone "$url" "$dir"
  fi
}

prepare_support_repos() {
  mkdirs
  clone_or_update "$BSYS_REPO_URL" "$ROOT/kit-cache/bsys"
  clone_or_update "$IMSSS_REPO_URL" "$ROOT/kit-cache/imsss"
}

prepare_build_tenex() {
  mkdirs
  clone_or_update "$BUILD_TENEX_REPO_URL" "$BUILD_TENEX"
  clone_or_update "$RCORNWELL_REPO_URL" "$RCORNWELL"
  echo "Prepared Lars build-tenex harness under $BUILD_TENEX"
  echo "Prepared Cornwell simulator checkout under $RCORNWELL"
}

verify_cornwell_patches() {
  prepare_build_tenex

  if [[ ! -f "$RCORNWELL_PATCH" ]]; then
    echo "Missing tracked Cornwell patch: $RCORNWELL_PATCH" >&2
    return 1
  fi

  if git -C "$RCORNWELL" apply --check "$RCORNWELL_PATCH" >/dev/null 2>&1; then
    echo "Cornwell BBN-TENEX patch is not applied yet, but applies cleanly."
    return 2
  fi

  if has_re 'if \(pi_enable\)' "$RCORNWELL/PDP10/kx10_cpu.c" \
    && ! has_re 'if \(pi_enable \|\| QBBN\)' "$RCORNWELL/PDP10/kx10_cpu.c" \
    && has_re 'pi_enc = 4;' "$RCORNWELL/PDP10/kx10_cpu.c" \
    && has_re 'if \(size == 0\)' "$RCORNWELL/PDP10/kx10_tym.c"; then
    echo "Cornwell BBN-TENEX patch is already present."
    return 0
  fi

  echo "Cornwell checkout is neither cleanly patchable nor already patched." >&2
  git -C "$RCORNWELL" status --short >&2 || true
  return 1
}

apply_cornwell_patches() {
  prepare_build_tenex
  if verify_cornwell_patches >/dev/null 2>&1; then
    echo "Cornwell BBN-TENEX patch already present."
    return 0
  fi
  git -C "$RCORNWELL" apply "$RCORNWELL_PATCH"
  echo "Applied Cornwell BBN-TENEX patch."
}

build_cornwell() {
  apply_cornwell_patches
  make -C "$RCORNWELL" pdp10-ki pdp10-ka
  [[ -x "$PDP10_KI" ]] || {
    echo "Expected pdp10-ki binary was not built: $PDP10_KI" >&2
    return 1
  }
  "$PDP10_KI" <<'EOF'
show version
exit
EOF
}

verify_build_tenex_media() {
  prepare_build_tenex
  (cd "$BUILD_TENEX/install/tools" && make -k)
  (cd "$BUILD_TENEX/install" && . ./media.sh && make_installation_media)

  local out="$TRANSCRIPTS/build-tenex-media.txt"
  "$BUILD_TENEX/install/tools/tendmp" -t "$BUILD_TENEX/install/media/syslod.dta" > "$out" 2>&1
  cat "$out"

  local missing=0
  for name in 'TENEX  SWP' 'TENEX  SAV' 'DLUSER SAV' 'USERS  TXT' 'DUMPER SAV' 'EXEC   SAV'; do
    if ! has_re "$name" "$out"; then
      echo "Missing expected syslod.dta entry: $name" >&2
      missing=1
    fi
  done
  return "$missing"
}

stage_build_tenex_support_files() {
  prepare_build_tenex
  prepare_support_repos

  local src_bugtable="$ROOT/kit-cache/imsss/files/system/bugtable.imsss-tenex.13132"
  local src_bugstrings="$ROOT/kit-cache/imsss/files/mon/bugstrings.imsss-tenex.13132"
  local dest_dir="$BUILD_TENEX/install/system"

  [[ -f "$src_bugtable" ]] || {
    echo "Missing IMSSS BUGTABLE source: $src_bugtable" >&2
    return 1
  }
  [[ -f "$src_bugstrings" ]] || {
    echo "Missing IMSSS BUGSTRINGS source: $src_bugstrings" >&2
    return 1
  }

  mkdir -p "$dest_dir"
  cp "$src_bugtable" "$dest_dir/bugtable.sumex-aim.13182"
  cp "$src_bugstrings" "$dest_dir/bugstrings.sumex-aim.13182"
  echo "Staged TENEX diagnostic support files in $dest_dir"
}

verify_build_tenex_system_tape() {
  stage_build_tenex_support_files
  (cd "$BUILD_TENEX/install/tools" && make -k)
  (cd "$BUILD_TENEX/install" && . ./media.sh && make_installation_media)

  local out="$TRANSCRIPTS/build-tenex-system-tape.txt"
  set +e
  (cd "$BUILD_TENEX/install" && timeout 20 ./tools/mini-dumper -tf media/system.tap) > "$out" 2>&1
  local rc=$?
  set -e
  # mini-dumper has been observed to keep reading after useful output. A
  # timeout is acceptable if the required directory entries were printed.
  if [[ "$rc" -ne 0 && "$rc" -ne 124 ]]; then
    echo "mini-dumper failed while listing system.tap; rc=$rc transcript=$out" >&2
    tail -80 "$out" >&2 || true
    return "$rc"
  fi

  cat "$out"
  local missing=0
  for name in \
    '<SYSTEM>BUGTABLE.SUMEX-AIM' \
    '<SYSTEM>BUGSTRINGS.SUMEX-AIM' \
    '<SYSTEM>EXEC.SAV' \
    '<SUBSYS>DUMPER.SAV'; do
    if ! has_fixed "$name" "$out"; then
      echo "Missing expected system.tap entry: $name" >&2
      missing=1
    fi
  done
  return "$missing"
}

write_build_tenex_hardware_do() {
  local hardware_do="$RUNTIME/build-tenex-hardware.do"
  sed \
    -e "s/attach -u dc 12345/attach -u dc $HOST69_DC_PORT/" \
    -e "s/attach -u tym 12346/attach -u tym $HOST69_TYM_PORT/" \
    "$BUILD_TENEX/install/simh/hardware.do" > "$hardware_do"
  printf '%s\n' "$hardware_do"
}

write_build_tenex_syslod_do() {
  local simh_do="$RUNTIME/build-tenex-syslod.do"
  local hardware_do
  hardware_do="$(write_build_tenex_hardware_do)"
  {
    printf 'do %s\n' "$hardware_do"
    printf 'attach -r dt0  media/syslod.dta\n'
    printf 'attach -r mta0 media/system.tap\n'
    printf 'expect "\\n" sleep 1; send "SYSLOD\\033G"; continue\n'
    printf 'expect "CLOBBER THE DISC BY RE-INITIALIZING?" send "Y"; continue\n'
    printf 'expect "\\n." send "I"; continue\n'
    printf 'expect "NIT BIT TABLE" send "."; continue\n'
    printf 'expect "READ BADSPOTS FROM FILE:" send "TTY:\\r"; continue\n'
    printf 'expect "[Confirm]" send "\\r"\n'
    printf 'load -c -s boot/tenex.sav\n'
    printf 'go 100\n'
  } > "$simh_do"
  printf '%s\n' "$simh_do"
}

write_build_tenex_install_files_do() {
  local simh_do="$RUNTIME/build-tenex-install-files.do"
  local hardware_do
  local step1="$RUNTIME/build-tenex-install-step1.do"
  local step2="$RUNTIME/build-tenex-install-step2.do"
  local step3="$RUNTIME/build-tenex-install-step3.do"
  local step4="$RUNTIME/build-tenex-install-step4.do"
  local step5="$RUNTIME/build-tenex-install-step5.do"
  local step6="$RUNTIME/build-tenex-install-step6.do"
  local step7="$RUNTIME/build-tenex-install-step7.do"
  local step8="$RUNTIME/build-tenex-install-step8.do"
  local step9="$RUNTIME/build-tenex-install-step9.do"
  local step10="$RUNTIME/build-tenex-install-step10.do"
  local step11="$RUNTIME/build-tenex-install-step11.do"
  local step12="$RUNTIME/build-tenex-install-step12.do"
  hardware_do="$(write_build_tenex_hardware_do)"
  {
    printf 'send "\\r"\n'
    printf 'sleep 2\n'
    printf 'send "\\032"\n'
    printf 'sleep 1\n'
    printf 'send "G"\n'
    printf 'noexpect\n'
    printf 'expect "ET FILE" do %s\n' "$step2"
    printf 'continue\n'
  } > "$step1"
  {
    printf 'send -t after=200000 delay=50000 "DTA0:EXEC.SAV\\r"\n'
    printf 'noexpect\n'
    printf 'expect "[Confirm]" do %s\n' "$step3"
    printf 'continue\n'
  } > "$step2"
  {
    printf 'noexpect\n'
    printf 'expect "\\n." do %s\n' "$step4"
    printf 'send "\\r"\n'
    printf 'continue\n'
  } > "$step3"
  {
    printf 'send -t delay=50000 "START.\\r"\n'
    printf 'noexpect\n'
    printf 'expect "MM/DD/YY HH:MM --" do %s\n' "$step5"
    printf 'continue\n'
  } > "$step4"
  {
    printf 'send -t delay=50000 "06/21/28 00:00\\r"\n'
    printf 'noexpect\n'
    printf 'expect "\\n@" do %s\n' "$step6"
    printf 'continue\n'
  } > "$step5"
  {
    printf 'send -t delay=50000 "ENABLE\\r"\n'
    printf 'noexpect\n'
    printf 'expect "\\n!" do %s\n' "$step7"
    printf 'continue\n'
  } > "$step6"
  {
    printf 'send -t delay=50000 "MOUNT DTA0:\\r"\n'
    printf 'noexpect\n'
    printf 'expect "\\n!" do %s\n' "$step8"
    printf 'continue\n'
  } > "$step7"
  {
    printf 'send -t delay=50000 "RUN DTA0:DLUSER.SAV\\r"\n'
    printf 'noexpect\n'
    printf 'expect "DUMP OR LOAD?" do %s\n' "$step9"
    printf 'continue\n'
  } > "$step8"
  {
    printf 'send "L"\n'
    printf 'noexpect\n'
    printf 'expect "FILE:" do %s\n' "$step10"
    printf 'continue\n'
  } > "$step9"
  {
    printf 'send -t delay=50000 "DTA0:USERS.TXT\\r"\n'
    printf 'noexpect\n'
    printf 'expect "[Old file]" do %s\n' "$step11"
    printf 'expect "DONE." do %s\n' "$step12"
    printf 'continue\n'
  } > "$step10"
  {
    printf 'send "\\r"\n'
    printf 'noexpect\n'
    printf 'expect "DONE." do %s\n' "$step12"
    printf 'continue\n'
  } > "$step11"
  {
    printf 'send -t delay=50000 "SYSTAT\\r"\n'
    printf 'continue\n'
  } > "$step12"
  {
    printf 'do %s\n' "$hardware_do"
    printf 'attach -r dt0  media/syslod.dta\n'
    printf 'attach -r mta0 media/system.tap\n'
    printf 'expect "\\n" sleep 1; send "SYSLOD\\033G"; continue\n'
    printf 'expect "CLOBBER THE DISC BY RE-INITIALIZING?" send "Y"; continue\n'
    printf 'expect "\\n." send "I"; continue\n'
    printf 'expect "NIT BIT TABLE" send "."; continue\n'
    printf 'expect "READ BADSPOTS FROM FILE:" send "TTY:\\r"; continue\n'
    printf 'expect "[Confirm]" do %s\n' "$step1"
    printf 'load -c -s boot/tenex.sav\n'
    printf 'go 100\n'
  } > "$simh_do"
  printf '%s\n' "$simh_do"
}

write_build_tenex_manual_console_do() {
  local simh_do="$RUNTIME/build-tenex-manual-console.do"
  local hardware_do
  hardware_do="$(write_build_tenex_hardware_do)"
  {
    printf 'do %s\n' "$hardware_do"
    printf 'attach -r dt0  media/syslod.dta\n'
    printf 'attach -r mta0 media/system.tap\n'
    printf 'expect "\\n" sleep 1; send "SYSLOD\\033G"; continue\n'
    printf 'expect "CLOBBER THE DISC BY RE-INITIALIZING?" send "Y"; continue\n'
    printf 'expect "\\n." send "I"; continue\n'
    printf 'expect "NIT BIT TABLE" send "."; continue\n'
    printf 'expect "READ BADSPOTS FROM FILE:" send "TTY:\\r"; continue\n'
    printf 'expect "[Confirm]" send "\\r"; continue\n'
    printf 'load -c -s boot/tenex.sav\n'
    printf 'go 100\n'
  } > "$simh_do"
  printf '%s\n' "$simh_do"
}

write_build_tenex_dc_probe_do() {
  local simh_do="$RUNTIME/build-tenex-dc-probe.do"
  local hardware_do
  hardware_do="$(write_build_tenex_hardware_do)"
  {
    printf 'do %s\n' "$hardware_do"
    printf 'attach -r dt0  media/syslod.dta\n'
    printf 'attach -r mta0 media/system.tap\n'
    printf 'expect "\\n" sleep 1; send "SYSLOD\\033G"; continue\n'
    printf 'expect "CLOBBER THE DISC BY RE-INITIALIZING?" send "Y"; continue\n'
    printf 'expect "\\n." send "I"; continue\n'
    printf 'expect "NIT BIT TABLE" send "."; continue\n'
    printf 'expect "READ BADSPOTS FROM FILE:" send "TTY:\\r"; continue\n'
    printf 'expect "[Confirm]" send "\\r"; continue\n'
    printf 'load -c -s boot/tenex.sav\n'
    printf 'go 100\n'
  } > "$simh_do"
  printf '%s\n' "$simh_do"
}

manual_install_console() {
  prepare_build_tenex
  verify_cornwell_patches
  verify_build_tenex_system_tape
  require_private_ports_clear

  [[ -x "$PDP10_KI" ]] || {
    echo "Cornwell pdp10-ki binary missing: $PDP10_KI" >&2
    echo "Run: $0 build-cornwell" >&2
    return 1
  }

  local simh_do
  simh_do="$(write_build_tenex_manual_console_do)"
  cat <<EOF
Starting private BBN-TENEX manual console.

This is the SIMH console path. It is NOT the public @L 69 host.
DC observation port:  127.0.0.1:$HOST69_DC_PORT
TYM observation port: 127.0.0.1:$HOST69_TYM_PORT

When the foreground console reaches the mini-exec dot prompt, try:
  ^Z
  G
  DTA0:EXEC.SAV

If you are at a SIMH "sim>" prompt instead of a TENEX "." prompt, use:
  send "\\032"
  continue
  send "G"
  continue

Stop with Ctrl-E to reach sim>, then:
  quit

Command file: $simh_do
EOF
  (cd "$BUILD_TENEX/install" && "$PDP10_KI" "$simh_do")
}

require_private_ports_clear() {
  local ss_out ps_out
  ps_out="$(ps -eo pid=,args= | awk '/pdp10-ki|drive-syslod|nc 127\\.0\\.0\\.1/ && $0 !~ /awk/ {print}' || true)"
  ss_out="$(ss -ltnp | filter_re "$HOST69_PORTS_RE" || true)"
  if [[ -n "$ps_out" || -n "$ss_out" ]]; then
    echo "Host69 private process/port state is not clean." >&2
    [[ -z "$ps_out" ]] || printf '%s\n' "$ps_out" >&2
    [[ -z "$ss_out" ]] || printf '%s\n' "$ss_out" >&2
    return 1
  fi
}

verify_build_tenex_dc_probe() {
  prepare_build_tenex
  verify_cornwell_patches
  verify_build_tenex_system_tape
  require_private_ports_clear

  [[ -x "$PDP10_KI" ]] || {
    echo "Cornwell pdp10-ki binary missing: $PDP10_KI" >&2
    echo "Run: $0 build-cornwell" >&2
    return 1
  }

  local simh_do out dc_out tym_out
  simh_do="$(write_build_tenex_dc_probe_do)"
  out="$TRANSCRIPTS/build-tenex-dc-probe.txt"
  dc_out="$TRANSCRIPTS/build-tenex-dc-probe-dc.txt"
  tym_out="$TRANSCRIPTS/build-tenex-dc-probe-tym.txt"

  echo "Running private Lars TENEX DC probe with ports $HOST69_DC_PORT/$HOST69_TYM_PORT..."
  : > "$out"
  : > "$dc_out"
  : > "$tym_out"
  (cd "$BUILD_TENEX/install" && "$PDP10_KI" "$simh_do") > "$out" 2>&1 &
  local sim_pid=$!

  local waited=0
  while [[ "$waited" -lt 20 ]]; do
    if ss -ltnp | filter_re ":$HOST69_DC_PORT|:$HOST69_TYM_PORT" >/dev/null; then
      break
    fi
    sleep 1
    waited=$((waited + 1))
  done

  {
    sleep "$BUILD_TENEX_BOOT_WAIT_SECS"
    printf '\r'
    sleep 30
  } | timeout 170 nc 127.0.0.1 "$HOST69_DC_PORT" > "$dc_out" 2>&1 &
  local dc_pid=$!

  {
    sleep "$BUILD_TENEX_BOOT_WAIT_SECS"
    printf '\r'
    sleep 2
    printf '\r'
    sleep 8
    printf '\r'
    sleep 20
  } | timeout 170 nc 127.0.0.1 "$HOST69_TYM_PORT" > "$tym_out" 2>&1 &
  local tym_pid=$!

  wait "$dc_pid" || true
  wait "$tym_pid" || true

  if kill -0 "$sim_pid" 2>/dev/null; then
    kill "$sim_pid" 2>/dev/null || true
    sleep 1
    kill -9 "$sim_pid" 2>/dev/null || true
  fi

  echo "Transcript: $out"
  tail -120 "$out" || true
  echo "DC transcript: $dc_out"
  tail -180 "$dc_out" || true
  echo "TYM transcript: $tym_out"
  tail -80 "$tym_out" || true

  if has_re 'TENEX IN OPERATION' "$out" "$dc_out" "$tym_out"; then
    echo "DC probe captured TENEX runtime. Review transcript before public routing."
    return 0
  fi

  echo "DC probe did not capture TENEX runtime. Host #69 remains private."
  return 2
}

verify_build_tenex_syslod_boot() {
  prepare_build_tenex
  verify_cornwell_patches
  verify_build_tenex_media
  require_private_ports_clear

  [[ -x "$PDP10_KI" ]] || {
    echo "Cornwell pdp10-ki binary missing: $PDP10_KI" >&2
    echo "Run: $0 build-cornwell" >&2
    return 1
  }

  local simh_do="$RUNTIME/build-tenex-syslod.do"
  local out="$TRANSCRIPTS/build-tenex-syslod.txt"
  local dc_out="$TRANSCRIPTS/build-tenex-syslod-dc.txt"
  local tym_out="$TRANSCRIPTS/build-tenex-syslod-tym.txt"
  simh_do="$(write_build_tenex_syslod_do)"

  echo "Running private Lars TENEX SYSLOD harness with ports $HOST69_DC_PORT/$HOST69_TYM_PORT..."
  : > "$out"
  : > "$dc_out"
  : > "$tym_out"
  (cd "$BUILD_TENEX/install" && "$PDP10_KI" "$simh_do") > "$out" 2>&1 &
  local sim_pid=$!

  local waited=0
  while [[ "$waited" -lt 20 ]]; do
    if ss -ltnp | filter_re ":$HOST69_DC_PORT|:$HOST69_TYM_PORT" >/dev/null; then
      break
    fi
    sleep 1
    waited=$((waited + 1))
  done

  sleep "$BUILD_TENEX_BOOT_WAIT_SECS"
  timeout 45 sh -c "printf '\\r' | nc 127.0.0.1 '$HOST69_DC_PORT'" > "$dc_out" 2>&1 || true
  timeout 12 sh -c "printf '\\r' | nc 127.0.0.1 '$HOST69_TYM_PORT'" > "$tym_out" 2>&1 || true

  if kill -0 "$sim_pid" 2>/dev/null; then
    kill "$sim_pid" 2>/dev/null || true
    sleep 1
    kill -9 "$sim_pid" 2>/dev/null || true
  fi

  echo "Transcript: $out"
  tail -120 "$out" || true
  echo "DC transcript: $dc_out"
  tail -120 "$dc_out" || true
  echo "TYM transcript: $tym_out"
  tail -80 "$tym_out" || true

  if has_re 'TENEX IN OPERATION' "$out" "$dc_out" "$tym_out"; then
    echo "TENEX monitor boot evidence found. Review transcript before public routing."
    return 0
  fi

  if has_re 'RUNNING DDMP|LOGIN JOB|BUGCHK' "$out" "$dc_out" "$tym_out"; then
    echo "SYSLOD reached TENEX runtime activity, but TENEX IN OPERATION was not captured."
    return 2
  fi

  echo "SYSLOD did not reach the disk initialization prompt. Host #69 remains private."
  return 2
}

verify_build_tenex_syslod() {
  verify_build_tenex_syslod_boot
}

verify_build_tenex_install_files() {
  prepare_build_tenex
  verify_cornwell_patches
  verify_build_tenex_system_tape
  require_private_ports_clear

  [[ -x "$PDP10_KI" ]] || {
    echo "Cornwell pdp10-ki binary missing: $PDP10_KI" >&2
    echo "Run: $0 build-cornwell" >&2
    return 1
  }

  local simh_do out rc
  simh_do="$(write_build_tenex_install_files_do)"
  out="$TRANSCRIPTS/build-tenex-install-files.txt"
  local dc_out="$TRANSCRIPTS/build-tenex-install-files-dc.txt"
  local tym_out="$TRANSCRIPTS/build-tenex-install-files-tym.txt"

  echo "Running private Lars TENEX install-files gate with ports $HOST69_DC_PORT/$HOST69_TYM_PORT..."
  : > "$out"
  : > "$dc_out"
  : > "$tym_out"
  (cd "$BUILD_TENEX/install" && "$PDP10_KI" "$simh_do") > "$out" 2>&1 &
  local sim_pid=$!

  local waited=0
  while [[ "$waited" -lt 20 ]]; do
    if ss -ltnp | filter_re ":$HOST69_DC_PORT|:$HOST69_TYM_PORT" >/dev/null; then
      break
    fi
    sleep 1
    waited=$((waited + 1))
  done

  sleep "$BUILD_TENEX_BOOT_WAIT_SECS"
  timeout 45 sh -c "printf '\\r' | nc 127.0.0.1 '$HOST69_DC_PORT'" > "$dc_out" 2>&1 || true
  timeout 12 sh -c "printf '\\r' | nc 127.0.0.1 '$HOST69_TYM_PORT'" > "$tym_out" 2>&1 || true

  if kill -0 "$sim_pid" 2>/dev/null; then
    kill "$sim_pid" 2>/dev/null || true
    sleep 1
    kill -9 "$sim_pid" 2>/dev/null || true
  fi

  echo "Transcript: $out"
  tail -180 "$out" || true
  echo "DC transcript: $dc_out"
  tail -120 "$dc_out" || true
  echo "TYM transcript: $tym_out"
  tail -80 "$tym_out" || true

  if has_re 'SYSTAT|JOB +USER|SUMEX-AIM Tenex|TENEX IN OPERATION' "$out" "$dc_out" "$tym_out" \
    && ! has_re 'NO EXEC|FAILED TO GTJFN/OPEN BUGTABLE FILE' "$out" "$dc_out" "$tym_out"; then
    echo "TENEX install-files evidence found. Review transcript before public routing."
    return 0
  fi

  echo "TENEX install-files gate did not pass. Host #69 remains private."
  return 2
}

verify_build_tenex_login() {
  echo "TENEX login gate is intentionally closed until install-files passes." >&2
  echo "No public @L 69 route is enabled by this script." >&2
  return 2
}

first_match() {
  local pattern="$1"
  find "$ROOT/kit-cache" -type f 2>/dev/null | { if command -v rg >/dev/null 2>&1; then rg -i "$pattern"; else grep -Ei "$pattern"; fi; } | sort | head -1 || true
}

survey_install_media() {
  prepare
  prepare_support_repos

  local out="$TRANSCRIPTS/install-media-survey.txt"
  {
    echo "BBN-TENEX host #69 install media survey"
    echo
    echo "Primary install recipe:"
    echo "  https://github.com/PDP-10/tenex/issues/18"
    echo
    echo "The public TENEX issue says the install path wants a bootable DECtape"
    echo "with TENEX.SAV and TENEX.SWP. Once the mini-exec is reached, it"
    echo "loads DLUSER.SAV, USERS.TXT, DUMPER.SAV, and a Dumper saveset."
    echo
    echo "Local evidence:"
    printf '  %-28s %s\n' "TENEX.SAV" "$(first_match '/TENEX[.]SAV$|/tenex[.]sav[.]')"
    printf '  %-28s %s\n' "TENEX.SWP" "$(first_match '/TENEX[.]SWP$|/tenex[.]swp[.]')"
    printf '  %-28s %s\n' "DLUSER.SAV" "$(first_match '/dluser[.]sav')"
    printf '  %-28s %s\n' "USERS.TXT" "$(first_match '/users[.]txt$|/users[.]txt[.]')"
    printf '  %-28s %s\n' "DUMPER.SAV" "$(first_match '/dumper[.]sav')"
    printf '  %-28s %s\n' "Dumper/BSYS tape images" "$(first_match '[.]tap$')"
    printf '  %-28s %s\n' "EXEC.SAV" "$(first_match '/exec[.]sav')"
    printf '  %-28s %s\n' "SYSJOB.SAV" "$(first_match '/sysjob[.]sav')"
    printf '  %-28s %s\n' "CHECKDSK.SAV" "$(first_match '/checkdsk[.]sav')"
    printf '  %-28s %s\n' "MDDT*.SAV" "$(first_match '/mddt.*[.]sav')"
    printf '  %-28s %s\n' "MACRO.SAV" "$(first_match '/macro[.]sav')"
    printf '  %-28s %s\n' "LOADER.SAV" "$(first_match '/loader[.]sav')"
    printf '  %-28s %s\n' "LINK*.SAV" "$(first_match '/link.*[.]sav')"
    printf '  %-28s %s\n' "TECO.SAV" "$(first_match '/teco[.]sav')"
    printf '  %-28s %s\n' "SOS.SAV" "$(first_match '/sos[.]sav')"
    printf '  %-28s %s\n' "READMAIL.SAV" "$(first_match '/readmail[.]sav')"
    printf '  %-28s %s\n' "AMON monitor files" "$(first_match '/amon[.]')"
    printf '  %-28s %s\n' "RLRMON files" "$(first_match '/rlrmon')"
    echo
    echo "Conclusion:"
    echo "  IMSSS supplies many needed TENEX system and subsystem files, including"
    echo "  DLUSER.SAV and DUMPER.SAV. The still-missing hard gate is a bootable"
    echo "  TENEX installation DECtape/disk path with TENEX.SWP and/or a proven"
    echo "  way to enter mini-exec SYSLOD on the simulator."
  } > "$out"

  cat "$out"
}

status() {
  mkdirs
  local matches
  echo "BBN-TENEX host #69 lab"
  echo "  root:        $ROOT"
  echo "  simh:        $SIM"
  echo "  tenex kit:   $KIT"
  echo "  runtime:     $RUNTIME"
  echo "  logs:        $LOGS"
  echo "  transcripts: $TRANSCRIPTS"
  echo "  public:      disabled; no @L 69 route is started by this script"
  echo "  boot gate:   verify-build-tenex-syslod-boot"
  echo "  files gate:  verify-build-tenex-install-files"
  echo "  login gate:  verify-build-tenex-login"
  echo "  build-tenex: $BUILD_TENEX"
  echo "  cornwell:    $RCORNWELL"
  echo "  pdp10-ki:    $PDP10_KI"
  matches="$(ps -eo pid=,args= | awk -v root="$ROOT" 'index($0, root) && $0 !~ /host69-bbn-tenexctl/ {print}' || true)"
  if [[ -n "$matches" ]]; then
    echo "$matches"
  else
    echo "  processes:   none using the host69 lab path"
  fi
}

stop() {
  mkdirs
  local pids=()
  local pid cwd comm
  while read -r pid comm; do
    [[ -n "$pid" ]] || continue
    cwd="$(readlink "/proc/$pid/cwd" 2>/dev/null || true)"
    if [[ "$cwd" == "$ROOT"* || "$cwd" == "$BUILD_TENEX"* ]]; then
      pids+=("$pid")
    fi
  done < <(ps -eo pid=,comm= | awk '$2 ~ /pdp10|simh|ka10|ki10/ {print $1, $2}')

  if [[ "${#pids[@]}" -eq 0 ]]; then
    echo "No host69 probe processes found."
    return 0
  fi
  echo "Stopping private host69 probe processes: ${pids[*]}"
  kill "${pids[@]}" 2>/dev/null || true
  sleep 1
  local survivors=()
  for pid in "${pids[@]}"; do
    if kill -0 "$pid" 2>/dev/null; then
      survivors+=("$pid")
    fi
  done
  if [[ "${#survivors[@]}" -gt 0 ]]; then
    echo "Hard-stopping private host69 probe processes: ${survivors[*]}"
    kill -9 "${survivors[@]}" 2>/dev/null || true
  fi
}

probe_config() {
  prepare
  local ini="$RUNTIME/probe-config.ini"
  local out="$TRANSCRIPTS/probe-config.txt"
  cp "$ROOT/host69-base.ini" "$ini"
  printf '\nexit\n' >> "$ini"
  echo "Running SIMH hardware config probe..."
  (cd "$ROOT" && timeout "$TIMEOUT_SECS" "$SIM" "$ini") > "$out" 2>&1 || {
    local rc=$?
    echo "Config probe exited rc=$rc; see $out"
    tail -80 "$out" || true
    return "$rc"
  }
  echo "Config probe transcript: $out"
  tail -80 "$out"
}

sanitize_label() {
  printf '%s' "$1" | tr '/[:upper:].' '_[:lower:]_'
}

write_load_ini() {
  local artifact="$1"
  local ini="$2"
  {
    cat "$ROOT/host69-base.ini"
    printf 'load %s/%s\n' "$KIT" "$artifact"
    printf 'show cpu\n'
    printf 'ex -m 0-20\n'
    printf 'go\n'
    printf 'exit\n'
  } > "$ini"
}

probe_load_one() {
  local artifact="$1"
  local label
  label="$(sanitize_label "$artifact")"
  local ini="$RUNTIME/probe-load-${label}.ini"
  local out="$TRANSCRIPTS/probe-load-${label}.txt"

  if [[ ! -f "$KIT/$artifact" ]]; then
    echo "Missing artifact: $KIT/$artifact"
    return 1
  fi

  write_load_ini "$artifact" "$ini"
  echo "Probing load/go for $artifact"
  set +e
  (cd "$ROOT" && timeout "$TIMEOUT_SECS" "$SIM" "$ini") > "$out" 2>&1
  local rc=$?
  set -e
  echo "  rc=$rc transcript=$out"
  tail -60 "$out"
  return 0
}

probe_load() {
  prepare
  local artifact
  for artifact in "${ARTIFACTS[@]}"; do
    probe_load_one "$artifact" || true
  done
}

verify() {
  verify_build_tenex_syslod_boot
  verify_build_tenex_install_files
  verify_build_tenex_login
}

case "${1:-status}" in
  prepare) prepare ;;
  prepare-build-tenex) prepare_build_tenex ;;
  verify-cornwell-patches) verify_cornwell_patches ;;
  apply-cornwell-patches) apply_cornwell_patches ;;
  build-cornwell) build_cornwell ;;
  verify-build-tenex-media) verify_build_tenex_media ;;
  verify-build-tenex-system-tape) verify_build_tenex_system_tape ;;
  verify-build-tenex-syslod-boot) verify_build_tenex_syslod_boot ;;
  verify-build-tenex-syslod) verify_build_tenex_syslod ;;
  verify-build-tenex-dc-probe) verify_build_tenex_dc_probe ;;
  verify-build-tenex-install-files) verify_build_tenex_install_files ;;
  verify-build-tenex-login) verify_build_tenex_login ;;
  manual-install-console) manual_install_console ;;
  status) status ;;
  stop) stop ;;
  probe-config) probe_config ;;
  probe-load) probe_load ;;
  survey-install-media) survey_install_media ;;
  verify) verify ;;
  *)
    echo "usage: $0 {prepare|prepare-build-tenex|verify-cornwell-patches|apply-cornwell-patches|build-cornwell|verify-build-tenex-media|verify-build-tenex-system-tape|verify-build-tenex-syslod-boot|verify-build-tenex-syslod|verify-build-tenex-dc-probe|verify-build-tenex-install-files|verify-build-tenex-login|manual-install-console|status|stop|probe-config|probe-load|survey-install-media|verify}" >&2
    exit 64
    ;;
esac
