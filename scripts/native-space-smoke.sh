#!/bin/bash
# Requires a logged-in GUI session and at least two existing native Desktops.
# Creates one disposable window in a separate process; never moves existing user windows.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/momentum-space-smoke.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
xcrun clang -fobjc-arc -framework AppKit -I "$root/Momentum" \
    "$root/scripts/native-space-smoke.m" "$root/Momentum/NativeSpaceMove.m" \
    -o "$tmp/native-space-smoke"
"$tmp/native-space-smoke"
