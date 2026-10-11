#!/usr/bin/env bash

# Ukrainian is available through Quickshell only. Mod+Space always toggles
# between English (index 0) and Russian (index 1), including when UA is active.
set -euo pipefail

current_index="$(niri msg -j keyboard-layouts | jq -r '.current_idx // 0')"
if [ "$current_index" = "0" ]; then
    niri msg action switch-layout 1
else
    niri msg action switch-layout 0
fi

quickshell ipc call panel refreshKeyboardLayout
