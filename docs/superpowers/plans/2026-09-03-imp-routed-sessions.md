# IMP-Routed Sessions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every browser `@L <host>` session carries its keystrokes and output through the simulated IMP network, with no path that bypasses the IMPs.

**Architecture:** Two routes only. (1) *Golden route*: the host's own NCP (ITS on 70/126/134/198, external PiDP-10 ITS on 41) answers ARPANET Telnet from a Linux TIP-side NCP. (2) *FEP route* (Oscar's front-end-processor method): a Linux NCP daemon (`ncpdov`) is attached to the host's IMP port, and an ARPANET Telnet server app bridges each accepted NCP connection to the simulator's terminal-line TCP port (hosts 1, 6, 11, 65). The SIMH-terminal-line bypass in `do.sh` and `mini/local-host-terminal.py` as a user-facing route are removed.

**Tech Stack:** bash, C (Lars Brinkhoff linux-ncp `ncpdov` + `ncp-telnet`), Python 3 (console-side line handshake), SIMH H316 IMPs, screen.

**Spec:** Oscar Vermeulen's email of 2026-08-29 (session transcript). Requirements: user session data flows through the IMP network for every host; FEP method acceptable where the node has no working NCP; native NCP preferred for ITS; branch to be mergeable back into obsolescence/arpanet under the name "Arpanet Recreation Project".

## Global Constraints

- No fallback route outside the IMP network. If the IMP route to a host is down, `do.sh` prints an explicit error and exits non-zero. Never reintroduce `local-host-terminal.py` as a route.
- Fail fast: unknown host numbers, missing NCP sockets, and missing binaries are errors, not defaults.
- Work on branch `feature/imp-routed-sessions` cut from `fork/main`; push to `fork` only. No PR to `origin` (obsolescence) without explicit user OK.
- Do not copy disk images between hosts. Each host keeps its own packs.
- Never sleep in long loops or poll indefinitely; every wait has a bounded timeout.
- Host 69 (BBN TENEX) stays disabled; it is out of scope.

---

## Current state (verified 2026-09-03)

| Host | System | Today's route (fork/main do.sh) | Target route |
| --- | --- | --- | --- |
| 1 | Sigma 7 CP-V | SIMH mux TCP 4003 (bypass) | FEP via ncpdov host 01 (IMP 1 port 0) |
| 6 | Multics MR12.8 | DPS8M HSLA TCP 6180 (bypass) | FEP via ncpdov host 06 (IMP 6 port 0, currently no daemon) |
| 11 | WAITS | `waitsconnect` FEP from ncp16 (through IMPs) | Keep FEP; migrate to generic FEP so one code path serves all |
| 41 | PiDP-10 ITS | Tailscale MTY line (bypass) | Golden: `ncp-telnet -c 41` from ncp31 |
| 65 | OS/360 TSO | frontdoor TCP 16515 (bypass) | FEP via ncpdov host 65 (IMP 1 port 1, currently no daemon) |
| 70/126/134/198 | KA ITS 1652 | SIMH terminal lines (bypass) | Golden: native ITS NCP with this branch's fixes |

Fixes that make the ITS golden route work live on `feature/its-ncp-debug` (commits 90d7ffd, c94457b, d0b9b76, ad3c2e2) and are **not** in `fork/main`.

---

### Task 1: Branch and merge the ITS NCP fixes

**Files:**
- Merge: `feature/its-ncp-debug` into new branch `feature/imp-routed-sessions`
- Conflict-prone: `mini/imp*.simh`, `mini/arpanet`, `stop-demo.sh`, `mini/noc/server/ncp.py`, `mini/waitsconnect`, `mini/ncpdov`

- [ ] **Step 1: Cut the branch**

```bash
cd /home/deltaprism/arpanet
git fetch fork
git checkout -b feature/imp-routed-sessions fork/main
```

- [ ] **Step 2: Merge the NCP fix branch**

```bash
git merge --no-ff feature/its-ncp-debug
```
Expected: conflicts in the files listed above. For `.simh` files keep `127.0.0.1` (never `localhost`). For binaries (`ncpdov`, `waitsconnect`) take the `feature/its-ncp-debug` side, then rebuild in Task 2 anyway.

- [ ] **Step 3: Rebuild ncpdov from merged source and confirm it runs**

```bash
make -C mini/src/ncpd-ovREUSE/src
cp mini/src/ncpd-ovREUSE/src/ncpd mini/ncpdov
./mini/ncpdov 2>&1 | head -3
```
Expected: usage text, exit non-zero (no args). No compiler errors.

- [ ] **Step 4: Commit**

```bash
git add -A mini/src/ncpd-ovREUSE mini/ncpdov mini/*.simh mini/arpanet stop-demo.sh mini/noc
git commit -m "Merge ITS NCP fixes into IMP-routed sessions branch"
```

---

### Task 2: Generic ARPANET Telnet FEP server (`ncp-telnet -s -- <command>`)

Today `ncp-telnet -s` accepts one NCP Telnet connection on socket 1 or 23 and runs `sh` on a pty (`mini/src/apps/telnet.c:414-508`). Change it to (a) run the command given after `--`, and (b) fork one child per accepted connection and keep listening, so many visitors can be on one host.

**Files:**
- Modify: `mini/src/apps/telnet.c:414-620`
- Build output: `mini/ncp-telnet`
- Test: `mini/tests/test_fep_echo.sh` (new)

**Interfaces:**
- Produces: `ncp-telnet -s[o] [-d] -- <cmd> [args...]` : listens on socket 23 (or 1 with `-o`), for each accepted connection forks and runs `<cmd>` on a pty with the connection bridged to it. Parent loops back to `ncp_listen`. Exits non-zero if `--` is missing.

- [ ] **Step 1: Write the failing test**

`mini/tests/test_fep_echo.sh`:
```bash
#!/usr/bin/env bash
# Round trip: TIP-side NCP (host 31) -> IMP network -> test NCP (host 02, SRI-ARC, no FEP host attached) -> `cat`.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ -S ncp31 && -S ncp02 ]] || { echo "ncp31/ncp02 sockets missing: start ./arpanet first"; exit 2; }
screen -dmS fep-test env NCP=ncp02 ./ncp-telnet -s -- cat
trap 'screen -S fep-test -X quit' EXIT
sleep 2
out=$(printf 'HELLO FEP\r\n' | timeout 30 env NCP=ncp31 ./ncp-telnet -c 2 2>/dev/null | tr -d '\r')
grep -q 'HELLO FEP' <<<"$out" || { echo "FAIL: no echo through IMP path; got: $out"; exit 1; }
echo "PASS: FEP round trip through IMPs"
```

- [ ] **Step 2: Run it to verify it fails**

```bash
chmod +x mini/tests/test_fep_echo.sh
./mini/arpanet start   # if not already running
./mini/tests/test_fep_echo.sh
```
Expected: FAIL, because `ncp-telnet -s -- cat` is rejected by the current `usage()` (extra args) or runs `sh` and never echoes `HELLO FEP`.

- [ ] **Step 3: Implement**

In `mini/src/apps/telnet.c`:

```c
/* replace the fixed shell command in telnet_server */
static char **server_cmd;          /* set from argv after "--" */

static void telnet_server (int host, int sock,
                           void (*process) (unsigned char, int, int),
                           const unsigned char *options)
{
  for (;;) {
    int connection, size;
    fprintf (stderr, "Listening to socket %d.\n", sock);
    size = 8;
    if (ncp_listen (sock, &size, &host, &connection) == -1) {
      fprintf (stderr, "NCP listen error.\n");
      exit (1);
    }
    pid_t pid = fork ();
    if (pid < 0) { perror ("fork"); exit (1); }
    if (pid == 0) {
      serve_connection (host, connection, process, options);   /* existing body, cmd = server_cmd */
      _exit (0);
    }
    /* parent: reap finished children without blocking */
    while (waitpid (-1, NULL, WNOHANG) > 0) ;
  }
}
```
Move the existing body (from `reader_fd = reader (connection);` to `ncp_close`) into `static void serve_connection (int host, int connection, ...)`, replacing `char *cmd[] = { "sh", NULL };` with `char **cmd = server_cmd;` and dropping the `"Welcome to Unix.\r\n"` banner write (the host prints its own banner).

In `main`, after option parsing:
```c
  if (telnet == telnet_server) {
    if (optind < argc && strcmp (argv[optind], "--") == 0)
      optind++;
    if (optind >= argc) {
      fprintf (stderr, "%s: -s requires -- <command> [args]\n", argv[0]);
      exit (1);
    }
    server_cmd = &argv[optind];
  }
```
Update `usage()` text to `-s[bno] [-d] -- command [args]`. Add `#include <sys/wait.h>` if absent.

- [ ] **Step 4: Build and run the test**

```bash
make -C mini/src/apps ncp-telnet && cp mini/src/apps/ncp-telnet mini/ncp-telnet
./mini/tests/test_fep_echo.sh
```
Expected: `PASS: FEP round trip through IMPs`. If `ncp-telnet -c 2` reports "Open refused" or times out, the ncpdov server-side ICP on socket 23 is the suspect: check `mini/logfiles/ncp02.log` for the RTS/STR sequence before changing anything.

- [ ] **Step 5: Run it twice concurrently to prove multi-session**

```bash
./mini/tests/test_fep_echo.sh & ./mini/tests/test_fep_echo.sh; wait
```
Expected: two PASS lines.

- [ ] **Step 6: Commit**

```bash
git add mini/src/apps/telnet.c mini/ncp-telnet mini/tests/test_fep_echo.sh
git commit -m "ncp-telnet -s: run a given command per connection, serve many sessions"
```

---

### Task 3: Console-side line bridge for the FEP (`mini/fep-line.py`)

The FEP child needs to do what `local-host-terminal.py` does today (connect to the simulator TCP line, strip SIMH's telnet negotiation, per-host handshake such as BREAK for CP-V or line selection, "busy" when all lines are taken), but with its stdin/stdout being the NCP connection's pty instead of the browser. Rename and reuse it; delete the old name so nothing can call it as a bypass.

**Files:**
- Rename: `mini/local-host-terminal.py` -> `mini/fep-line.py` (`git mv`)
- Modify: `mini/fep-line.py` : remove the `"TELNET to host N."` print (the TIP-side `ncp-telnet -c` already prints it) and the `--connect-host` option (FEP lines are always local).

- [ ] **Step 1: Move and edit**

```bash
git mv mini/local-host-terminal.py mini/fep-line.py
```
Edit docstring to: `"""FEP console side: bridge an NCP Telnet session (stdin/stdout) to a local simulator terminal line."""`. Delete the `print(f"TELNET to host ...")` line and the `--connect-host` argument; use `"127.0.0.1"` in `create_connection`.

- [ ] **Step 2: Direct test against Multics line**

```bash
cd mini && ./host06-multicsctl.sh start
printf '\r' | timeout 15 ./fep-line.py 006 6180 --no-init --select-first-line --max-simh-line 7 | head -5
```
Expected: Multics HSLA banner text, then exit when stdin closes.

- [ ] **Step 3: Commit**

```bash
git add -A mini/fep-line.py
git commit -m "Rename local-host-terminal.py to fep-line.py; console side of the FEP only"
```

---

### Task 4: FEP host table and supervisor (`mini/fep-hosts.conf`, `mini/fepctl.sh`)

**Files:**
- Create: `mini/fep-hosts.conf`
- Create: `mini/fepctl.sh`
- Modify: `mini/arpanet` (`start_ncpds`, `stop_ncpds`, `start_network`, `stop_hosts`)

**Interfaces:**
- `fep-hosts.conf` line format: `host_decimal:ncp_socket:line_port:fep-line flags`
- `fepctl.sh {start|stop|status} <host|all>`; screen name `fep<host>`.

- [ ] **Step 1: Write the table**

`mini/fep-hosts.conf`:
```
# host : NCP socket : simulator line TCP port : fep-line.py flags
1:ncp01:4003:--no-init --send-break --max-simh-line 7
6:ncp06:6180:--no-init --select-first-line --max-simh-line 7
65:ncp65:16515:--no-init
```
(Host 11 joins in Task 6 once WAITS is verified on the generic path.)

- [ ] **Step 2: Write the supervisor**

`mini/fepctl.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
CONF=fep-hosts.conf
action="${1:?usage: fepctl.sh start|stop|status host|all}"
target="${2:?usage: fepctl.sh start|stop|status host|all}"

rows() { grep -v '^#' "$CONF" | grep -v '^$'; }
row_for() { rows | awk -F: -v h="$1" '$1==h'; }

start_one() {
    local row="$1"
    IFS=: read -r host ncp port flags <<<"$row"
    [[ -S "$ncp" ]] || { echo "fep$host: NCP socket $ncp missing (is ncpdov for host $host running?)" >&2; exit 1; }
    ss -H -ltn | grep -q ":$port " || { echo "fep$host: simulator line port $port not listening" >&2; exit 1; }
    screen -ls | grep -q "[.]fep$host[[:space:]]" && { echo "fep$host already running"; return; }
    # shellcheck disable=SC2086
    screen -dmS "fep$host" env NCP="$ncp" ./ncp-telnet -s -- ./fep-line.py "$host" "$port" $flags
    echo "fep$host: ARPANET TELNET server on $ncp -> line port $port"
}
stop_one() { IFS=: read -r host _ <<<"$1"; screen -S "fep$host" -X quit 2>/dev/null || true; echo "fep$host stopped"; }
status_one() { IFS=: read -r host _ <<<"$1"; screen -ls | grep -q "[.]fep$host[[:space:]]" && echo "fep$host: up" || echo "fep$host: down"; }

if [[ "$target" == all ]]; then list=$(rows); else list=$(row_for "$target"); [[ -n "$list" ]] || { echo "no FEP entry for host $target" >&2; exit 1; }; fi
while IFS= read -r row; do "${action}_one" "$row"; done <<<"$list"
```

- [ ] **Step 3: Enable the missing NCP daemons in `mini/arpanet`**

In the `NCPS` array uncomment `"01:1:65:21011:21012:UCLA-CCn"` and `"06:0:06:20061:20062:MIT-MULTICS"`. Confirm `imp01.simh` `hi2` is `21011:127.0.0.1:21012` and `imp06.simh` `hi1` is `20061:127.0.0.1:20062` (they are). Update the "Started N NCP daemons" count.

- [ ] **Step 4: Wire fepctl into start/stop**

In `start_network()` after `start_ncpds` (or where NCPs are started in this deployment), add `./fepctl.sh start all`. In `stop_hosts()` add `./fepctl.sh stop all` before killing simulators.

- [ ] **Step 5: Verify FEP hosts over the IMPs**

```bash
cd mini && ./arpanet stop && ./arpanet start && ./fepctl.sh status all
for h in 1 6 65; do printf '\r' | timeout 30 env NCP=ncp31 ./ncp-telnet -c $h 2>&1 | head -4; done
```
Expected: `fep1/6/65: up`; CP-V `LOGON PLEASE`, Multics HSLA banner, and the CCN front door prompt, each arriving via `ncp-telnet -c` (that is, through IMP 31 -> ... -> IMP 1 / IMP 6).

- [ ] **Step 6: Commit**

```bash
git add mini/fep-hosts.conf mini/fepctl.sh mini/arpanet
git commit -m "Add FEP supervisor: ncpdov + ncp-telnet -s bridge hosts 1, 6, 65 onto their IMP ports"
```

---

### Task 5: Remove the bypass from `do.sh`

**Files:**
- Modify: `do.sh:44-90`
- Modify: `mini/dotelnet.sh`

**Interfaces:**
- `do.sh` reads `@L n` / `@O n`, picks the TIP-side NCP, and `exec`s `mini/dotelnet.sh IMP HOSTIDX DEST CMD`. Nothing else.

- [ ] **Step 1: Delete the case block**

Remove everything from the comment `# Several ITS hosts reject or stall ARPANET TELNET ...` through the closing `fi` of the `case`. Replace with a source-NCP table that is explicit and fails fast:

```bash
# TIP-side NCP used as the visitor's source host. Host 11 is only reachable
# from AMES ncp16 today (see docs/hosted-terminal-fixes.md, open issue).
case "$DEST" in
    11|013) IMP_NUMBER=16 ;;
    *)      IMP_NUMBER=31 ;;
esac
HOST_NUMBER=0
if [[ ! -S "mini/ncp$IMP_NUMBER" ]]; then
    echo "TIP NCP ncp$IMP_NUMBER is not running; cannot reach host $DEST over the ARPANET" >&2
    exit 1
fi
```

- [ ] **Step 2: Make `dotelnet.sh` fail loudly**

Add `set -euo pipefail` at the top and replace the trailing `NCP=... ./ncp-telnet ...` with `exec env NCP="ncp$IMP" ./ncp-telnet -c $TELNET_MODE $HOST "$DEST"` so a refused open surfaces `ncp-telnet`'s own error to the browser.

- [ ] **Step 3: Verify no bypass remains**

```bash
grep -rn "local-host-terminal\|fep-line" do.sh web-terminals/ ; echo "exit=$?"
```
Expected: no matches (`exit=1`).

- [ ] **Step 4: Browser-path smoke test**

```bash
printf '@L 6\r' | SESSION_NUMBER=0 timeout 40 ./do.sh | head -5
```
Expected: `TELNET to host 6.` from ncp-telnet, then the Multics banner.

- [ ] **Step 5: Commit**

```bash
git add do.sh mini/dotelnet.sh
git commit -m "do.sh: every @L goes through the IMP network; remove SIMH terminal-line bypass"
```

---

### Task 6: Move Stanford WAITS (host 11) onto the generic FEP

`waitsconnect` is a single-session, hard-coded (`console_port=1025`, IMP ports 20111/20112, sends `login\r` after a delay) FEP. Replace it with an `fep-hosts.conf` row so all FEP hosts share one code path, keeping the login nudge.

**Files:**
- Modify: `mini/fep-hosts.conf`, `mini/fep-line.py` (add `--send-after-connect STRING` and `--delay SECONDS`), `mini/host11ctl.sh` (stop starting `waitsconnect`; start `fepctl.sh start 11`), `mini/arpanet` (uncomment `"11:0:11:20111:20112:SU-AI"`).
- Delete: `mini/waitsconnect`, `mini/src/waits-ncpd/` (only after Step 3 passes).

- [ ] **Step 1: Add the option to `fep-line.py`**

```python
parser.add_argument("--send-after-connect", default=None,
                    help="bytes (python escapes) written to the line after the initial drain")
parser.add_argument("--delay", type=float, default=0.0,
                    help="seconds to wait before --send-after-connect")
```
After `initial_output = drain_initial_output(...)`:
```python
if args.send_after_connect is not None:
    time.sleep(args.delay)
    sock.sendall(args.send_after_connect.encode().decode("unicode_escape").encode())
```

- [ ] **Step 2: Add the row**

```
11:ncp11:1025:--no-init --delay 2 --send-after-connect login\r
```

- [ ] **Step 3: Verify from ncp16 and from ncp31**

```bash
cd mini && ./host11ctl.sh restart 11 && ./fepctl.sh start 11
for n in 16 31; do printf '\r' | timeout 40 env NCP=ncp$n ./ncp-telnet -c 11 2>&1 | head -6; done
```
Expected: WAITS login prompt via ncp16. If ncp31 still fails, record the failing `ncp31.log` lines in the commit message; that is the existing open issue, not a regression.

- [ ] **Step 4: Remove waitsconnect and commit**

```bash
git rm -r mini/waitsconnect mini/src/waits-ncpd
git add -A mini
git commit -m "Host 11 WAITS on the generic FEP; retire waitsconnect"
```

---

### Task 7: ITS golden route on all four hosted ITS machines

`feature/its-ncp-debug` proved a real NCP login on host 126 with three fixes. Apply them to 70, 134, 198 and make the route the only route.

**Files:**
- Modify: `mini/host70/mini-run`, `mini/host134/mini-run`, `mini/host198/mini-run` (`set ch dis` -> `set ch enabled` + `set ch node=177002`)
- Modify: `mini/hostctl.sh` (launch `pdp10-ka-fixed` instead of `pdp10-ka` for all four; error if the binary is missing)
- Rebuild: `mini/h316ov` from a source that includes the open-simh H316 host port 3/4 device-address swap (open-simh PR #522), needed by 134 (port 2 -> hi3) and 198 (port 3 -> hi4)

- [ ] **Step 1: Confirm the H316 fix is available**

```bash
cd src/sims && git log --oneline -3 -- H316/h316_imp.c; git log --all --grep='522' --oneline | head
```
If absent, fetch the PR branch from `open-simh/simh`, build `h316`, copy to `mini/h316ov`. Record the commit hash in `CHANGELOG.md`.

- [ ] **Step 2: Apply the mini-run and binary changes, restart IMP 6 with its hosts**

```bash
cd mini && ./impctl.py stop 6 && ./impctl.py start 6 && ./hostctl.sh restart all
```

- [ ] **Step 3: Verify each ITS host answers over the network**

```bash
for h in 70 126 134 198; do printf '\r' | timeout 60 env NCP=ncp31 ./ncp-telnet -c $h 2>&1 | grep -m1 -E "turist|ITS" || echo "host $h: NO ANSWER"; done
```
Expected: four ITS banners. Any `Open refused` goes to Step 4.

- [ ] **Step 4: Stabilize intermittent `Open refused` (systematic-debugging)**

Reproduce with the same loop 10 times per host; for each refusal capture `mini/logfiles/ncp31.log` and the host's `ncp<host>.log` around the RTS/STR/CLS lines. Localize to one of: TIP-side RFC timeout still too short, ITS TELSER job-slot exhaustion, or RFNM accounting after a prior session. Fix the single root cause found; re-run the 10x loop and require 10/10 per host before moving on. Do not add retries in `do.sh`.

- [ ] **Step 5: Commit**

```bash
git add mini/host*/mini-run mini/hostctl.sh mini/h316ov CHANGELOG.md
git commit -m "ITS hosts 70/134/198: Chaosnet device, fixed KAIMP emulator, H316 port 3/4 fix; native NCP logins"
```

---

### Task 8: IMP + ITS restart coupling

ITS cannot re-attach to an IMP after start. `hostctl.sh restart <its-host>` must therefore restart the host's IMP first and then every ITS host on that IMP, in that order.

**Files:**
- Modify: `mini/hostctl.sh:220-240` (`restart_host`)

- [ ] **Step 1: Implement**

```bash
imp_of() { case "$1" in 70|134|198) echo 6 ;; 126) echo 62 ;; *) echo "no IMP mapping for host $1" >&2; exit 1 ;; esac; }
hosts_on_imp() { case "$1" in 6) echo "70 134 198" ;; 62) echo "126" ;; esac; }
restart_host() {
    local imp; imp=$(imp_of "$1")
    for h in $(hosts_on_imp "$imp"); do stop_host "$h"; done
    ./impctl.py stop "$imp"; ./impctl.py start "$imp"
    sleep 3   # IMP host interface must be listening before ITS boots (bounded, one-shot)
    for h in $(hosts_on_imp "$imp"); do start_host "$h"; done
}
```

- [ ] **Step 2: Verify**

```bash
cd mini && ./hostctl.sh restart 134 && ./hostctl.sh status all
printf '\r' | timeout 60 env NCP=ncp31 ./ncp-telnet -c 134 2>&1 | grep -m1 turist
```
Expected: 70, 134, 198 all up; host 134 banner over the network after the coupled restart.

- [ ] **Step 3: Commit**

```bash
git add mini/hostctl.sh
git commit -m "hostctl restart: restart the IMP and all ITS hosts on it together"
```

---

### Task 9: External PiDP-10 host 41 on native NCP

**Files:**
- Modify: `docs/hosted-terminal-fixes.md` (host 41 row)

- [ ] **Step 1: Verify** (only where the Tailscale IMP41 link exists; skip with a note otherwise)

```bash
cd mini && printf '\r' | timeout 60 env NCP=ncp31 ./ncp-telnet -c 41 2>&1 | head -4
```
Expected: ITS banner from the Pi. `do.sh` already routes 41 through `dotelnet.sh` after Task 5; no code change.

---

### Task 10: Verification entry point (`make check`)

`testrepo` cannot pick a command for this repo. Proposed single entry point: a top-level `Makefile` with a `check` target. **Needs user OK before adding (per-repo scaffolding).**

**Files:**
- Create: `Makefile`, `mini/verify-imp-routing.sh`

- [ ] **Step 1: Write the check**

`mini/verify-imp-routing.sh`:
```bash
#!/usr/bin/env bash
# Every public host must answer ARPANET TELNET from the TIP-side NCP, and do.sh must have no bypass.
set -euo pipefail
cd "$(dirname "$0")"
fail=0
grep -q "local-host-terminal\|fep-line" ../do.sh && { echo "FAIL: do.sh contains a non-IMP route"; fail=1; }
while IFS=: read -r host ncp expect; do
    if printf '\r' | timeout 60 env NCP="$ncp" ./ncp-telnet -c "$host" 2>&1 | grep -q -E "$expect"; then
        echo "PASS host $host via $ncp"
    else
        echo "FAIL host $host via $ncp (expected /$expect/)"; fail=1
    fi
done <<'EOT'
1:ncp31:LOGON PLEASE
6:ncp31:Multics
11:ncp16:WAITS|Stanford|login
65:ncp31:UCLA|CCN|TSO
70:ncp31:turist|ITS
126:ncp31:turist|ITS
134:ncp31:turist|ITS
198:ncp31:turist|ITS
EOT
./tests/test_fep_echo.sh
exit $fail
```
`Makefile`:
```make
check:
	./mini/verify-imp-routing.sh
.PHONY: check
```

- [ ] **Step 2: Run**

```bash
testrepo   # should now select: make check
```
Expected: all PASS lines, exit 0.

- [ ] **Step 3: Commit**

```bash
git add Makefile mini/verify-imp-routing.sh
git commit -m "Add make check: every host must answer over the IMP network"
```

---

### Task 11: Docs, PR, and reply to Oscar

**Files:**
- Modify: `docs/hosted-terminal-fixes.md` (routing table: every row says "via ARPANET TELNET from ncpNN"; delete the "Hosted Browser Routing" split paragraph), `docs/host-lifecycle.md` (FEP section, coupled restart), `CHANGELOG.md` (dated entry), `README.md` (replace "Host 11 ... Linuxbridge" sentence with the FEP list: 1, 6, 11, 65).
- Rename in copy: "Kurt Hamm's Arpanet" -> "Arpanet Recreation Project" wherever it appears (`grep -rn "Kurt Hamm's" arpa/ *.html README.md`).

- [ ] **Step 1: Edit docs and commit**

```bash
git add docs CHANGELOG.md README.md arpa
git commit -m "Docs: all sessions IMP-routed; FEP hosts listed; project name restored"
```

- [ ] **Step 2: Push and open the PR on the fork**

```bash
git push fork feature/imp-routed-sessions
gh pr create --repo kurthamm/arpanet --base main --title "Route every browser session through the IMP network" --body "..."
gh pr checks --watch   # CodeRabbit; address all IMPORTANT findings
```

- [ ] **Step 3: Reply to Oscar** with the draft from this session, updated with the verified host list. Upstream PR to obsolescence/arpanet only when the user says so.

---

## Self-review

- Spec coverage: session data through IMPs for every host (Tasks 4-7, 9, verified by 10); FEP where no NCP (Tasks 2-4, 6); native NCP for ITS (7, 8); mergeable/renamed (11). Host 69 explicitly excluded.
- Placeholders: none. The one judgment call left open is the source-NCP oddity for host 11 (ncp16 works, ncp31 does not), recorded as an open issue rather than hidden.
- Names used consistently: `fep-line.py`, `fepctl.sh`, `fep-hosts.conf`, `ncp-telnet -s -- <cmd>`, `verify-imp-routing.sh`.
- Risk worth stating up front: Task 2 depends on `ncpdov` handling the server side of the Telnet ICP on socket 23 for a `listen`ing app. `finser` proves `ncp_listen` works for a plain socket; the ICP case is verified by the Task 2 test before anything else is built on it.

---

### Task 5b: Restore Oscar's TIP-side source rotation

The original `do.sh` rotated browser sessions over eight TIP-side NCPs (`imp_host_pairs` in `origin/main:do.sh`). The fork collapsed this to CCA (31) because two of the eight sources, host 74 (LL-TX2, IMP 10 port 1) and host 78 (CMU-10A, IMP 14 port 1), have their NCP daemons commented out in `mini/arpanet` while their IMP host interfaces are attached, so those sessions silently failed.

**Files:**
- Modify: `do.sh` (source selection), `mini/arpanet` (NCPS entries `10:1:74:21101:21102:LL-TX2`, `14:1:78:21141:21142:CMU-10A`)

- [ ] **Step 1:** Restore the `imp_host_pairs` array and `SESSION_NUMBER` bounds check from `origin/main:do.sh`; derive `IMP_NUMBER`/`HOST_NUMBER` from it. Keep the host 11 → ncp16 exception and the fail-fast socket check. The socket name for a port-1 host is its full host number (`ncp74`, `ncp78`), so compute it from the NCPS mapping, not from the IMP number.
- [ ] **Step 2:** Uncomment the two NCPS entries; restart the network (NCPs before IMPs) and confirm `mini/ncp74` and `mini/ncp78` exist and `NCP=ncp74 ./ncp-ping 1` answers.
- [ ] **Step 3:** For SESSION_NUMBER 0..7 run `(printf '@L 1\r\n'; sleep 8) | SESSION_NUMBER=$n timeout 40 ./do.sh | head -3` and require the CP-V banner from every source.
- [ ] **Step 4:** Commit.

**Task 11 additions (from deviation audit):** add a caveat on `arpa/arpanet-node-6-MIT.html` that host 6 runs public Multics MR12.8 media, not recovered 1972 MIT Multics, and replace the real-person site/administrator names in `mini/host06-multicsctl.sh` with generic ones; restore the pointers to Oscar's Google Group and obsolescence.dev in `arpanet_home.html`, `arpanet_about.html`, `README.md`.

---

### Task 4b: FEP supervisor under systemd (droplet deployment)

The droplet starts everything from `deploy/systemd/*.service`, not `./arpanet start`. Add `deploy/systemd/arpanet-fep.service` (User=deltaprism, WorkingDirectory=/home/deltaprism/arpanet/mini, After=arpanet-noc.service, ExecStart runs a small `mini/fep-wait-and-start.sh` that waits (bounded, 60 s) for the NCP sockets named in `fep-hosts.conf` then `./fepctl.sh start all`, ExecStop=`./fepctl.sh stop all`, Restart=on-failure). Move the bounded socket wait out of `mini/arpanet` into that script so both entry points share it. Document in `deploy/README.md`. Verify with `systemd-analyze verify deploy/systemd/arpanet-fep.service` locally; live verification happens on the droplet after merge.

**Merge target:** `fork/host69-tenex-ncp-imp` (the branch the droplet runs), not `main`.
