#!/usr/bin/env bash

set -euo pipefail

readonly launcher_path="$HOME/.config/hypr/launcher"
readonly request="${1:-toggle}"

ipc_call() {
    if [[ "$request" == "wallpaper" ]]; then
        quickshell ipc --path "$launcher_path" call launcher wallpaper 2>/dev/null
    else
        quickshell ipc --path "$launcher_path" call launcher toggle 2>/dev/null
    fi
}

# The normal path is a single IPC round trip to the already warm launcher.
if ipc_call; then
    exit 0
fi

# Session startup fallback: start the daemon once, then open it as soon as IPC
# becomes available.
env QSG_RENDER_LOOP=threaded quickshell --daemonize --no-duplicate \
    --path "$launcher_path"

for _ in {1..50}; do
    if [[ "$request" == "wallpaper" ]]; then
        if quickshell ipc --path "$launcher_path" call launcher wallpaper 2>/dev/null; then
            exit 0
        fi
    elif quickshell ipc --path "$launcher_path" call launcher open 2>/dev/null; then
        exit 0
    fi
    sleep 0.02
done

exit 1
