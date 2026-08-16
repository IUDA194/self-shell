#!/usr/bin/env bash

set -euo pipefail

readonly settings_path="$HOME/.config/hypr/settings"
readonly wallpaper="${1:-}"

open_settings() {
  if [[ -n "$wallpaper" ]]; then
    quickshell ipc --path "$settings_path" call settings appearance "$wallpaper" 2>/dev/null
  else
    quickshell ipc --path "$settings_path" call settings open 2>/dev/null
  fi
}

open_settings && exit 0

env QSG_RENDER_LOOP=threaded quickshell --daemonize --no-duplicate --path "$settings_path"
for _ in {1..50}; do
  open_settings && exit 0
  sleep 0.02
done

exit 1
