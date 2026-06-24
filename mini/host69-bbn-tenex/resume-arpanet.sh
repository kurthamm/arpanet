#!/bin/sh
cd "$(dirname "$0")"
n=0
for p in $(cat frozen-pids.txt); do kill -CONT "$p" 2>/dev/null && n=$((n+1)); done
echo "resumed $n processes"
