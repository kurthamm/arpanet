#!/bin/sh
# Reset host69 disk packs to a clean base so the SYSLOD re-init won't spin on
# leftover cruft. Keeps the patched syslod.dta (DLUSER) and system.tap.
set -e
cd /home/deltaprism/arpanet/mini/host69-bbn-tenex
if pgrep -x pdp10-ki >/dev/null 2>&1; then
  echo "Stop the sim first (Ctrl-E then 'quit')." >&2; exit 1
fi
SRC=kit-cache/build-tenex/media
DST=kit-cache/build-tenex/install/media
for n in 0 1 2 3 4 5 6; do
  cp -f "$SRC/tenex$n.rp03" "$DST/tenex$n.rp03"
done
echo "disk packs reset to clean base. Now run:  ./run-host69.sh"
