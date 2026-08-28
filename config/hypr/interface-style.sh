#!/usr/bin/env bash

set -euo pipefail

readonly style_file="${XDG_CONFIG_HOME:-$HOME/.config}/self-shell/interface-style.json"
readonly state_dir="${XDG_RUNTIME_DIR:-/tmp}/self-shell"
readonly state_file="$state_dir/minimum-style.json"
readonly palette_script="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/apply-palette.sh"

current_style() {
  jq -r '.style // "modern"' "$style_file" 2>/dev/null || printf 'modern\n'
}

write_setting() {
  local filter="$1" value="$2" temporary_file
  mkdir -p "${style_file%/*}"
  temporary_file="$(mktemp "${style_file%/*}/interface-style.XXXXXX")"
  if [[ -s "$style_file" ]]; then
    jq --arg value "$value" "$filter" "$style_file" > "$temporary_file"
  else
    jq -cn --arg value "$value" '{style:"modern",panelPosition:"left",colorMode:"wallpaper",fixedScheme:"default",opacity:0.94} | '"$filter" > "$temporary_file"
  fi
  mv -f -- "$temporary_file" "$style_file"
}

active_workspace() {
  hyprctl -j activeworkspace | jq -er '.id'
}

toggle_allfloat() {
  local target_workspace="$1" current_workspace
  current_workspace="$(active_workspace)"
  if [[ "$current_workspace" == "$target_workspace" ]]; then
    hyprctl dispatch workspaceopt allfloat >/dev/null
  else
    hyprctl --batch "dispatch workspace $target_workspace; dispatch workspaceopt allfloat; dispatch workspace $current_workspace" >/dev/null
  fi
}

apply_minimum() {
  local workspace temporary_state
  workspace="$(active_workspace)"
  mkdir -p "$state_dir"

  # Older versions of Minimum enabled allfloat. Turn it back off once so the
  # gapless tiler can make windows occupy the complete usable screen.
  if [[ -e "$state_file" ]] && [[ "$(jq -r '.allfloat // true' "$state_file" 2>/dev/null)" == "true" ]]; then
    local previous_workspace
    previous_workspace="$(jq -er '.workspace' "$state_file" 2>/dev/null || true)"
    if [[ "$previous_workspace" =~ ^-?[0-9]+$ ]]; then
      toggle_allfloat "$previous_workspace"
    fi
  fi

  temporary_state="$(mktemp "$state_dir/minimum-style.XXXXXX")"
  jq -cn --argjson workspace "$workspace" '{workspace:$workspace,allfloat:false}' > "$temporary_state"
  mv -f -- "$temporary_state" "$state_file"

  # Performance-first gapless tiling. Keep only short, functional motion so
  # window and workspace changes remain readable without feeling decorative.
  hyprctl --batch 'keyword animations:enabled true; keyword animation windows,1,2,default,popin 98%; keyword animation windowsOut,1,1,default,popin 98%; keyword animation fade,1,2,default; keyword animation workspaces,1,2,default,slide; keyword animation border,0; keyword decoration:blur:enabled false; keyword decoration:shadow:enabled false; keyword decoration:rounding 0; keyword general:gaps_in 0; keyword general:gaps_out 1; keyword general:border_size 1' >/dev/null
}

apply_modern() {
  local workspace
  workspace="$(jq -er '.workspace' "$state_file" 2>/dev/null || true)"
  hyprctl reload >/dev/null
  if [[ "$workspace" =~ ^-?[0-9]+$ ]] && [[ "$(jq -r '.allfloat // true' "$state_file" 2>/dev/null)" == "true" ]]; then
    toggle_allfloat "$workspace"
  fi
  rm -f -- "$state_file"
  [[ ! -x "$palette_script" ]] || "$palette_script" >/dev/null 2>&1 || true
}

set_style() {
  local style="$1"
  case "$style" in modern|minimum) ;; *) printf 'Unknown interface style: %s\n' "$style" >&2; exit 2 ;; esac
  write_setting '.style = $value' "$style"
  apply_style "$style"
}

set_panel_position() {
  local panel_position="$1"
  case "$panel_position" in left|top) ;; *) printf 'Unknown panel position: %s\n' "$panel_position" >&2; exit 2 ;; esac
  write_setting '.panelPosition = $value' "$panel_position"
}

set_placement() {
  local key="$1" value="$2"
  case "$key" in launcherPosition|notificationPosition|notificationCenterPosition|clipboardPosition) ;; *) exit 2 ;; esac
  write_setting ".$key = \$value" "$value"
}

set_opacity() {
  local opacity="$1"
  [[ "$opacity" =~ ^(0\.[0-9]+|1(\.0+)?)$ ]] || { printf 'Invalid opacity: %s\n' "$opacity" >&2; exit 2; }
  awk -v value="$opacity" 'BEGIN { exit !(value >= 0.35 && value <= 1) }' || { printf 'Opacity must be between 0.35 and 1\n' >&2; exit 2; }
  write_setting '.opacity = ($value | tonumber)' "$opacity"
}

apply_style() {
  case "$1" in
    minimum) apply_minimum ;;
    *) apply_modern ;;
  esac
}

case "${1:-get}" in
  get) current_style ;;
  set) set_style "${2:-}" ;;
  set-position) set_panel_position "${2:-}" ;;
  set-placement) set_placement "${2:-}" "${3:-}" ;;
  set-opacity) set_opacity "${2:-}" ;;
  apply) apply_style "$(current_style)" ;;
  *) printf 'Usage: %s [get|set modern|set minimum|set-position left|set-position top|set-opacity 0.35..1|apply]\n' "${0##*/}" >&2; exit 2 ;;
esac
