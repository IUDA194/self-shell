#!/usr/bin/env bash
set -euo pipefail

# Waybar and this shell reserve the same left edge, so keep only one of them.
pkill -x waybar 2>/dev/null || true
exec quickshell --no-duplicate --path "${XDG_CONFIG_HOME:-${HOME}/.config}/quickshell"
