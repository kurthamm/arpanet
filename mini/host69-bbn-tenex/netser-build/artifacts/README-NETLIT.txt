NETCRL.REL / netlit.rel provenance
==================================
NETSER-lite (milestone 1a: listen on ARPANET login socket 1, observe GDSTS).
Built 2026-06-27 on emulated BBN-TENEX / SUMEX-AIM 1.31.82 (rcornwell pdp10-ki),
using the on-box FAIL assembler (build-tenex fail.sav) + PA1050.

Two walls had to be cleared first:
 1. FAIL requires CRLF source line-endings. LF-only (unix/tendmp default) makes FAIL
    count lines but never recognize END -> "FATAL END OF FILE & NO END STMT".
    Fix: sed 's/$/\r/' netser-lite.fai > NETCRL.FAI  (CRLF) before tendmp.
 2. TENEX dskasn allocator BUGHLTs (140046) on any *growing* DSK write (FAIL .REL
    output, COPY TTY:, LOADER .SAV). Fixed-size DTA->DSK COPY is fine. Fix: keep
    assembly I/O off DSK -- source from DECtape DTA1, output .REL to writable DTA0.

Assembly: FAIL  *DTA0:NETCRL_DTA1:NETCRL.FAI  ->  "PROGRAM BREAK 000206'" (clean).
Preserve: kill -TERM (NOT -9) the SIMH ki so the buffered DECtape flushes; tendmp -x.
tendmp confirmed NETCRL.REL (7 blocks) on the tape. Extracted artifact = netlit.rel.

Files:
  netser-lite.fai          master source (LF)
  NETCRL.FAI               CRLF source that FAIL actually assembled
  netlit.rel               the assembled object (3855 bytes)
  scratch-NETCRL-REL.dta   full writable DECtape image holding NETCRL.REL
  SHA256SUMS.txt           checksums
