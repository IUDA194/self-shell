#!/usr/bin/env bash

set -euo pipefail

# Replace an old watcher if Hyprland restarts without cleaning the process up.
pkill -fx "wl-paste --type text --watch ${HOME}/.config/hypr/clipboard-store.sh" 2>/dev/null || true

exec wl-paste --type text --watch "${HOME}/.config/hypr/clipboard-store.sh"
