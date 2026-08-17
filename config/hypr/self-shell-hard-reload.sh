#!/usr/bin/env bash

set -uo pipefail

readonly config_root="${XDG_CONFIG_HOME:-${HOME}/.config}"

# Give the settings action enough time to return before its Quickshell instance
# is stopped. This script is launched in a detached session.
sleep 0.2

configs=(
  "$config_root/quickshell"
  "$config_root/hypr/dashboard"
  "$config_root/hypr/launcher"
  "$config_root/hypr/command-center"
  "$config_root/hypr/screenshot"
  "$config_root/hypr/settings"
)

for config in "${configs[@]}"; do
  printf 'Stopping %s\n' "$config"
  quickshell kill --path "$config" >/dev/null 2>&1 || true
done

# Instance shutdown is asynchronous. Without this pause, --no-duplicate may
# still see the old process and skip its replacement.
sleep 1

hyprctl reload >/dev/null 2>&1 || true

start_shell() {
  local config="$1"
  printf 'Starting %s\n' "$config"
  env QSG_RENDER_LOOP=threaded quickshell --daemonize --no-duplicate \
    --path "$config" || printf 'Failed to start %s\n' "$config"
}

start_shell "$config_root/quickshell"
start_shell "$config_root/hypr/dashboard"
start_shell "$config_root/hypr/launcher"
start_shell "$config_root/hypr/command-center"
start_shell "$config_root/hypr/screenshot"

# Reopen settings to make it clear that the reload completed successfully.
printf 'Reopening settings\n'
"$config_root/hypr/settings.sh" || {
  printf 'Failed to reopen settings; starting its shell directly\n'
  start_shell "$config_root/hypr/settings"
}
