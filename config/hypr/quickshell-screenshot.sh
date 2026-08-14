#!/usr/bin/env bash

set -euo pipefail

freeze_path="${XDG_RUNTIME_DIR:-/tmp}/self-shell-screenshot-freeze-${UID}.png"
readonly screenshot_path="${XDG_CONFIG_HOME:-${HOME}/.config}/hypr/screenshot"

# Low PNG compression makes the selection overlay appear noticeably sooner.
grim -l 1 "$freeze_path"
export SELF_SHELL_SCREENSHOT_FREEZE="$freeze_path"

# Usually this is only one IPC round trip to the warm screenshot daemon.
if quickshell ipc --path "$screenshot_path" call screenshot open 2>/dev/null; then
    exit 0
fi

# Startup fallback in case the daemon has not become ready yet.
env SELF_SHELL_SCREENSHOT_FREEZE="$freeze_path" QSG_RENDER_LOOP=threaded \
    quickshell --daemonize --no-duplicate --path "$screenshot_path"

for _ in {1..50}; do
    if quickshell ipc --path "$screenshot_path" call screenshot open 2>/dev/null; then
        exit 0
    fi
    sleep 0.02
done

rm -f "$freeze_path"
exit 1
