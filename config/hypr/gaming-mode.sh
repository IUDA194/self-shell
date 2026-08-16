#!/usr/bin/env bash

set -euo pipefail

readonly state_dir="${XDG_RUNTIME_DIR:-/tmp}/self-shell"
readonly state_file="$state_dir/gaming-mode.json"
readonly palette_script="$HOME/.config/hypr/apply-palette.sh"

notify() {
  command -v notify-send >/dev/null 2>&1 || return 0
  notify-send -a "Self Shell" -i applications-games "$1" "$2"
}

active_workspace() {
  hyprctl -j activeworkspace | jq -er '.id'
}

workspace_allfloat() {
  local target_workspace="$1" current_workspace
  current_workspace="$(active_workspace)"

  if [[ "$current_workspace" != "$target_workspace" ]]; then
    hyprctl --batch "dispatch workspace $target_workspace; dispatch workspaceopt allfloat; dispatch workspace $current_workspace" >/dev/null
  else
    hyprctl dispatch workspaceopt allfloat >/dev/null
  fi
}

enable_mode() {
  local workspace temporary_state
  workspace="$(active_workspace)"
  mkdir -p "$state_dir"
  temporary_state="$(mktemp "$state_dir/gaming-mode.XXXXXX")"
  jq -cn --argjson workspace "$workspace" '{enabled:true,workspace:$workspace}' > "$temporary_state"
  mv -f -- "$temporary_state" "$state_file"

  # allfloat disables automatic tiling for this workspace and is reversible.
  workspace_allfloat "$workspace"
  hyprctl --batch 'keyword animations:enabled false; keyword decoration:blur:enabled false; keyword decoration:shadow:enabled false; keyword decoration:rounding 0; keyword general:gaps_in 0; keyword general:gaps_out 0; keyword general:border_size 0' >/dev/null

  notify "Игровой режим включён" "Анимации и эффекты выключены, тайлинг приостановлен на рабочей области $workspace."
}

disable_mode() {
  local workspace
  workspace="$(jq -er '.workspace' "$state_file" 2>/dev/null || true)"

  # Reload restores the user's configured visual settings in one operation.
  hyprctl reload >/dev/null
  if [[ "$workspace" =~ ^-?[0-9]+$ ]]; then
    workspace_allfloat "$workspace"
  fi
  rm -f -- "$state_file"

  # The active wallpaper palette is applied at runtime and must follow reload.
  if [[ -x "$palette_script" ]]; then
    "$palette_script" >/dev/null 2>&1 || true
  fi
  notify "Игровой режим выключен" "Эффекты и тайлинг восстановлены."
}

case "${1:-toggle}" in
  on)
    [[ -e "$state_file" ]] || enable_mode
    ;;
  off)
    [[ ! -e "$state_file" ]] || disable_mode
    ;;
  toggle)
    if [[ -e "$state_file" ]]; then disable_mode; else enable_mode; fi
    ;;
  status)
    if [[ -e "$state_file" ]]; then printf 'on\n'; else printf 'off\n'; fi
    ;;
  *)
    printf 'Usage: %s [on|off|toggle|status]\n' "${0##*/}" >&2
    exit 2
    ;;
esac
