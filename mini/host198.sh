#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
exec ./hostctl.sh start 198
