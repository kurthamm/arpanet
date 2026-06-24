; BBN-TENEX host #69 — full unattended install (Lars syslod.do structure).
; Run with cwd = build-tenex/install and stdout redirected to a FILE (not a
; pty): the monitor's re-init wedges under an interactive pty console but boots
; cleanly under a file-redirected console.
;
; Phasing is essential. SIMH expect rules are one-shot and are ALL checked
; against console output while the CPU runs. If the EXEC-install rules were
; registered before the disk-init `go`, their patterns (\n. , [Confirm], ...)
; fire on disk-init output and inject stray keystrokes that wedge the re-init.
; So each phase registers only its own rules, ended by a no-continue expect
; that stops the CPU; a bare `continue` then resumes for the next phase.

do simh/hardware.do
attach -r dt0  media/syslod.dta
attach -r mta0 media/system.tap

; --- phase 1: SYSLOD re-init, bit-table init, badspots; stop at no-EXEC ---
expect "\n" sleep 1; send "SYSLOD\033G"; continue
expect "RE-INITIALIZING?" send "Y"; continue
expect "\n." send "I"; continue
expect "NIT BIT TABLE" send "."; continue
expect "READ BADSPOTS FROM FILE:" send "TTY:\r"; continue
expect "[Confirm]" send "\r"

load -c -s boot/tenex.sav
go 100

; --- phase 2: load EXEC from DECtape, START, set date, save EXEC + users ---
expect "\n" send "\032"; continue
expect "\n." send "G"; continue
expect "ET FILE" send "DTA0:EXEC.SAV\r"; continue
expect "[Confirm]" send "\r"; continue
expect "\n." send "S"; continue
expect "TART" send "."; continue
expect "MM/DD/YY HH:MM" send "06/21/26 12:00:00\r"; continue
expect "\n@" send "ENABLE\r"; continue
expect "\n!" send "MOUNT DTA0:\r"; continue
expect "\n!" send "GET DTA0:EXEC.SAV\r"; continue
expect "\n!" send "SSAVE 0 777 EXEC.SAV\r"; continue
expect "[New file]" send "\r"; continue
expect "\n!" send "RUN DTA0:DLUSER.SAV\r"; continue
expect "DUMP OR LOAD?" send "L"; continue
expect "FILE:" send "DTA0:USERS.TXT\r"; continue
expect "[Old file]" send "\r"; continue
expect "DONE."
continue

; --- phase 3: install DUMPER into <SUBSYS> ---
expect "\n!" send "GET DTA0:DUMPER.SAV\r"; continue
expect "\n!" send "SSAVE 0 777 <SUBSYS>DUMPER.SAV\r"; continue
expect "[New file]" send "\r"
continue

; --- done: wait for EXEC prompt, then stop and flush the installed disk ---
expect "\n!"
detach all
quit
