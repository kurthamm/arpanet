#!/usr/bin/env python3
"""Reliable pexpect driver for the BBN-TENEX host #69 lab.

This replaces the fragile SIMH queued-`expect` chain (which collides on
repeated prompts such as "\\n.", "\\n!", and "[Confirm]") with a patient,
one-prompt-at-a-time pexpect conversation against the pdp10-ki console.

Modes:
  install   Boot from media, run SYSLOD to (re)initialize the disk, then
            install EXEC, the user directory, and DUMPER onto the disk via
            the TENEX no-EXEC mini-exec, and cleanly flush the disk on exit.
  run       Boot the already-installed disk (no re-init) and prove a real
            login: LOGIN OPERATOR, SYSTAT, DIRECTORY, LOGOUT.
  full      install then run, in two separate simulator sessions.

Nothing here enables the public @L 69 route. This is the private lab only.
"""

import argparse
import os
import sys
import time

import pexpect

HERE = os.path.dirname(os.path.abspath(__file__))
INSTALL = os.path.join(HERE, "kit-cache", "build-tenex", "install")
PDP10_KI = os.environ.get(
    "PDP10_KI",
    os.path.join(HERE, "kit-cache", "rcornwell-sims", "BIN", "pdp10-ki"),
)
RUNTIME = os.path.join(HERE, "runtime")
TRANSCRIPTS = os.path.join(HERE, "transcripts")

DC_PORT = int(os.environ.get("HOST69_DC_PORT", "16945"))
TYM_PORT = int(os.environ.get("HOST69_TYM_PORT", "16946"))

WRU = "\034"   # console break-to-sim> char, per `set console wru=034`
ESC = "\033"
CTRL_Z = "\032"

# Account used to validate login; defined in install/boot/users.txt.
LOGIN_USER = os.environ.get("HOST69_LOGIN_USER", "OPERATOR")
LOGIN_PASS = os.environ.get("HOST69_LOGIN_PASS", "OPERATOR")
LOGIN_ACCT = os.environ.get("HOST69_LOGIN_ACCT", "OPERATOR")


def log(msg):
    print("[drive-tenex] %s" % msg, flush=True)


def make_hardware_do():
    """Derive a hardware.do that listens on the lab's private DC/TYM ports."""
    src = os.path.join(INSTALL, "simh", "hardware.do")
    with open(src) as fh:
        text = fh.read()
    text = text.replace("attach -u dc 12345", "attach -u dc %d" % DC_PORT)
    text = text.replace("attach -u tym 12346", "attach -u tym %d" % TYM_PORT)
    os.makedirs(RUNTIME, exist_ok=True)
    dst = os.path.join(RUNTIME, "drive-hardware.do")
    with open(dst, "w") as fh:
        fh.write(text)
    return dst


def make_boot_do(reinit):
    """A do-file that sets up hardware, attaches media, and drives the SYSLOD
    disk dialogue via SIMH's own `expect`/`send`.

    This part must be SIMH-driven, not pexpect-driven. Two things break when
    pexpect types into the free-running console instead:
      * `SYSLOD<ESC>G` only rings DDT's bell (a documented failure); SIMH's
        paced `send` injection during `go 100` is reliable.
      * Answering the clobber prompt by hand leaves the monitor wedged in
        "TENEX RESTARTING, WAIT..." forever, whereas SIMH `send ...; continue`
        boots cleanly through to "TENEX IN OPERATION / NO EXEC".
    Every rule carries `continue`, so after the dialogue the CPU keeps running
    and pexpect can take over the no-EXEC mini-exec. The rules are one-shots, so
    they cannot collide with the later pexpect conversation.

    For install we re-initialize the disk (clobber = Y) and run the bit-table
    init + badspots dialogue. For run we keep the installed file system
    (clobber = N)."""
    hardware = make_hardware_do()
    lines = [
        "do %s" % hardware,
        "attach -r dt0  media/syslod.dta",
        "attach -r mta0 media/system.tap",
        'expect "\\n" sleep 1; send "SYSLOD\\033G"; continue',
    ]
    if reinit:
        lines += [
            'expect "RE-INITIALIZING?" send "Y"; continue',
            'expect "\\n." send "I"; continue',
            'expect "NIT BIT TABLE" send "."; continue',
            'expect "READ BADSPOTS FROM FILE:" send "TTY:\\r"; continue',
            'expect "[Confirm]" send "\\r"; continue',
        ]
    else:
        lines += [
            'expect "RE-INITIALIZING?" send "N"; continue',
        ]
    lines += [
        "load -c -s boot/tenex.sav",
        "go 100",
    ]
    os.makedirs(RUNTIME, exist_ok=True)
    name = "drive-boot-%s.do" % ("install" if reinit else "run")
    dst = os.path.join(RUNTIME, name)
    with open(dst, "w") as fh:
        fh.write("\n".join(lines) + "\n")
    return dst


def spawn(do_file, logname):
    os.makedirs(TRANSCRIPTS, exist_ok=True)
    logpath = os.path.join(TRANSCRIPTS, logname)
    logfh = open(logpath, "wb")
    log("simulator: %s %s" % (PDP10_KI, do_file))
    log("console transcript: %s" % logpath)
    child = pexpect.spawn(
        PDP10_KI,
        [do_file],
        cwd=INSTALL,
        encoding="latin-1",
        codec_errors="replace",
        timeout=180,
        dimensions=(48, 120),
    )
    child.logfile_read = LogTee(logfh)
    return child


class LogTee:
    """Tee simulator output to both the transcript file and our stdout."""

    def __init__(self, fh):
        self.fh = fh

    def write(self, data):
        self.fh.write(data.encode("latin-1", "replace"))
        self.fh.flush()
        sys.stdout.write(data)
        sys.stdout.flush()

    def flush(self):
        self.fh.flush()


def expect_one(child, pattern, timeout=180):
    """Wait for a single literal/regex pattern, with a useful failure dump."""
    try:
        child.expect(pattern, timeout=timeout)
    except pexpect.TIMEOUT:
        log("TIMEOUT waiting for: %r" % pattern)
        log("---- last 1500 chars of console buffer ----")
        sys.stdout.write(child.before[-1500:])
        sys.stdout.flush()
        log("---- end buffer ----")
        raise
    except pexpect.EOF:
        log("EOF (simulator exited) while waiting for: %r" % pattern)
        raise


CHAR_DELAY = float(os.environ.get("HOST69_CHAR_DELAY", "0.06"))


def slow_send(child, text):
    """Send one character at a time, teletype-paced.

    The simulated console drops characters that arrive faster than the
    keyboard interrupt service can absorb them, so every keystroke is paced
    and ESC (altmode) gets an extra beat before the following character."""
    for ch in text:
        child.send(ch)
        time.sleep(0.18 if ch == ESC else CHAR_DELAY)


def step(child, await_pat, send, label, timeout=180, end="", settle=0.4):
    log("step: %s  (await %r -> send %r)" % (label, await_pat, send))
    expect_one(child, await_pat, timeout=timeout)
    if settle:
        time.sleep(settle)
    if send is not None:
        slow_send(child, send + end)


def do_install(child):
    """Drive the EXEC/users/DUMPER install on the freshly initialized disk.

    The do-file owns the whole SYSLOD dialogue (clobber, bit-table init,
    badspots) via SIMH expect. We wait out the multi-minute disk re-init, then
    take over the no-EXEC mini-exec once it returns to the dot prompt."""
    # Disk re-init writes the whole rp03 set ("TENEX RESTARTING, WAIT...") and
    # can run for several minutes in simulation before "TENEX IN OPERATION /
    # NO EXEC" appears. Be very patient here.
    expect_one(child, "NO EXEC", timeout=600)
    log("reached NO EXEC mini-exec")
    # The do-file's last SYSLOD rule answers the badspots [Confirm]; sync our
    # read position past it, then nudge the mini-exec back to a dot prompt.
    expect_one(child, r"\[Confirm\]", timeout=120)
    log("disk init complete (badspots confirmed)")
    time.sleep(1.0)
    slow_send(child, CTRL_Z)
    # Load EXEC.SAV from the install DECtape and START it.
    step(child, r"\r?\n\.", "G", "mini-exec: GET FILE", timeout=60, settle=0.8)
    step(child, "ET FILE", "DTA0:EXEC.SAV", "get EXEC.SAV", end="\r", timeout=60)
    step(child, r"\[Confirm\]", "", "confirm get EXEC", end="\r", timeout=60)
    step(child, r"\r?\n\.", "S", "mini-exec: START", timeout=60, settle=0.6)
    step(child, "TART", ".", "execute START", timeout=60)
    # EXEC is now running: set date/time, then enable and install onto disk.
    step(child, "MM/DD/YY HH:MM", "06/21/26 12:00:00", "set date/time",
         end="\r", timeout=120, settle=0.6)
    step(child, r"\r?\n@", "ENABLE", "ENABLE", end="\r", timeout=120,
         settle=0.6)
    step(child, r"\r?\n!", "MOUNT DTA0:", "mount install dectape", end="\r",
         timeout=60, settle=0.6)
    step(child, r"\r?\n!", "GET DTA0:EXEC.SAV", "get EXEC into EXEC", end="\r",
         timeout=60, settle=0.6)
    step(child, r"\r?\n!", "SSAVE 0 777 EXEC.SAV", "save EXEC to disk",
         end="\r", timeout=60, settle=0.6)
    step(child, r"\[New file\]", "", "confirm new EXEC file", end="\r",
         timeout=60)
    step(child, r"\r?\n!", "RUN DTA0:DLUSER.SAV", "run DLUSER", end="\r",
         timeout=60, settle=0.6)
    step(child, "DUMP OR LOAD\\?", "L", "DLUSER: load", timeout=60)
    step(child, "FILE:", "DTA0:USERS.TXT", "DLUSER users file", end="\r",
         timeout=60)
    step(child, r"\[Old file\]", "", "confirm users file", end="\r", timeout=60)
    expect_one(child, "DONE.", timeout=120)
    log("DLUSER reports DONE")
    # Install DUMPER into <SUBSYS>.
    step(child, r"\r?\n!", "GET DTA0:DUMPER.SAV", "get DUMPER", end="\r",
         timeout=60, settle=0.6)
    step(child, r"\r?\n!", "SSAVE 0 777 <SUBSYS>DUMPER.SAV", "save DUMPER",
         end="\r", timeout=60, settle=0.6)
    step(child, r"\[New file\]", "", "confirm new DUMPER file", end="\r",
         timeout=60)
    expect_one(child, r"\r?\n!", timeout=60)
    log("install steps complete; flushing disk")
    shutdown(child)


def do_run(child):
    """Boot the installed disk and validate a real login.

    The do-file owns SYSLOD<ESC>G and declines re-init (clobber = N) to keep
    the installed file system."""
    expect_one(child, "TENEX IN OPERATION", timeout=300)
    log("TENEX IN OPERATION")
    # We want the EXEC login banner / @ prompt. Nudge with a CR.
    time.sleep(2)
    child.send("\r")
    idx = child.expect([r"@", "NO EXEC"], timeout=120)
    if idx == 1:
        log("FAIL: booted disk still reports NO EXEC")
        shutdown(child)
        return False
    log("EXEC present; attempting login")
    step(child, r"@", "LOGIN %s %s %s" % (LOGIN_USER, LOGIN_PASS, LOGIN_ACCT),
         "LOGIN", end="\r", timeout=60, settle=0.6)
    # A successful login lands back at the @ EXEC prompt with a job number.
    idx = child.expect([r"@", "INCORRECT", "ILLEGAL", "\\?"], timeout=120)
    if idx != 0:
        log("FAIL: login was rejected")
        shutdown(child)
        return False
    log("login accepted; running SYSTAT / DIRECTORY")
    step(child, r"@", "SYSTAT", "SYSTAT", end="\r", timeout=60, settle=0.6)
    step(child, r"@", "DIRECTORY", "DIRECTORY", end="\r", timeout=60,
         settle=0.6)
    step(child, r"@", "LOGOUT", "LOGOUT", end="\r", timeout=60, settle=0.6)
    time.sleep(2)
    log("login validation sequence sent")
    shutdown(child)
    return True


def shutdown(child):
    """Break to sim> and quit so attached disks are flushed."""
    try:
        time.sleep(1)
        child.send(WRU)
        child.expect(r"sim>", timeout=30)
        child.sendline("quit")
        child.expect(pexpect.EOF, timeout=30)
    except (pexpect.TIMEOUT, pexpect.EOF):
        pass
    finally:
        if child.isalive():
            child.terminate(force=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["install", "run", "full"])
    args = ap.parse_args()

    if not os.access(PDP10_KI, os.X_OK):
        log("pdp10-ki not executable: %s" % PDP10_KI)
        return 2

    if args.mode in ("install", "full"):
        log("=== INSTALL phase ===")
        do_file = make_boot_do(reinit=True)
        child = spawn(do_file, "drive-install.txt")
        try:
            do_install(child)
        except (pexpect.TIMEOUT, pexpect.EOF):
            shutdown(child)
            return 3

    if args.mode in ("run", "full"):
        log("=== RUN/validate phase ===")
        do_file = make_boot_do(reinit=False)
        child = spawn(do_file, "drive-run.txt")
        try:
            ok = do_run(child)
        except (pexpect.TIMEOUT, pexpect.EOF):
            shutdown(child)
            return 3
        return 0 if ok else 4

    return 0


if __name__ == "__main__":
    sys.exit(main())
