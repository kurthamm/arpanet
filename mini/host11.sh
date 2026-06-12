#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
exec ./host11ctl.sh start 11
