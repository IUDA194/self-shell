#!/usr/bin/env bash
set -euo pipefail

for _ in {1..30}; do
    if quickshell ipc --path "$HOME/.config/hypr/command-center" \
        call commandCenter notifications 2>/dev/null; then
        exit 0
    fi
    sleep 0.1
done

exit 1
