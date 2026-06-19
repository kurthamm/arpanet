#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/host69-bbn-tenex" && pwd)"
REPO="$(cd "$ROOT/../.." && pwd)"
SIM="${SIM:-$REPO/mini/host70/pdp10-ka}"
KIT="$ROOT/kit-cache/tenex"
RUNTIME="$ROOT/runtime"
LOGS="$ROOT/logs"
TRANSCRIPTS="$ROOT/transcripts"
TIMEOUT_SECS="${TIMEOUT_SECS:-10}"

TENEX_REPO_URL="${TENEX_REPO_URL:-https://github.com/PDP-10/tenex.git}"
BSYS_REPO_URL="${BSYS_REPO_URL:-https://github.com/PDP-10/bsys.git}"
IMSSS_REPO_URL="${IMSSS_REPO_URL:-https://github.com/PDP-10/imsss.git}"

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
    git -C "$dir" pull --ff-only >/dev/null
  else
    git clone "$url" "$dir"
  fi
}

prepare_support_repos() {
  mkdirs
  clone_or_update "$BSYS_REPO_URL" "$ROOT/kit-cache/bsys"
  clone_or_update "$IMSSS_REPO_URL" "$ROOT/kit-cache/imsss"
}

first_match() {
  local pattern="$1"
  find "$ROOT/kit-cache" -type f 2>/dev/null | rg -i "$pattern" | sort | head -1 || true
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
  matches="$(ps -eo pid=,args= | awk -v root="$ROOT" 'index($0, root) && $0 !~ /host69-bbn-tenexctl/ {print}' || true)"
  if [[ -n "$matches" ]]; then
    echo "$matches"
  else
    echo "  processes:   none using the host69 lab path"
  fi
}

stop() {
  mkdirs
  local matches
  matches="$(pgrep -af "$SIM|host69-bbn-tenex|pdp10-ka.*host69" || true)"
  if [[ -z "$matches" ]]; then
    echo "No host69 probe processes found."
    return 0
  fi
  echo "$matches"
  echo "Refusing to kill broad PDP-10/SIMH matches automatically; host69 probes are run under timeout and should exit."
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
  probe_config
  probe_load
  if rg -i "BBN-TENEX|TENEX IN OPERATION|SYSTEM-A EXEC|LOGIN|@" "$TRANSCRIPTS"/probe-load-*.txt >/dev/null 2>&1; then
    echo "Possible TENEX banner/login text found. Review transcripts before any public route change."
    return 0
  fi
  echo "No TENEX boot/login banner found. Host #69 remains private lab only."
  return 2
}

case "${1:-status}" in
  prepare) prepare ;;
  status) status ;;
  stop) stop ;;
  probe-config) probe_config ;;
  probe-load) probe_load ;;
  survey-install-media) survey_install_media ;;
  verify) verify ;;
  *)
    echo "usage: $0 {prepare|status|stop|probe-config|probe-load|survey-install-media|verify}" >&2
    exit 64
    ;;
esac
