#!/usr/bin/env bash
set -euo pipefail

# Waybar and this shell reserve the same left edge, so keep only one of them.
pkill -x waybar 2>/dev/null || true
# Niri exposes NIRI_SOCKET to processes started from its config.  Preserve it
# explicitly so the shared shell can select Niri IPC instead of Hyprland IPC.
if [[ -n "${NIRI_SOCKET:-}" ]]; then
    export SELF_SHELL_COMPOSITOR=niri
else
    export SELF_SHELL_COMPOSITOR=hyprland
fi

exec quickshell --no-duplicate --path "${XDG_CONFIG_HOME:-${HOME}/.config}/quickshell"
