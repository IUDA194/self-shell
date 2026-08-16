#!/usr/bin/env bash

set -euo pipefail

readonly waypaper_config="${XDG_CONFIG_HOME:-$HOME/.config}/waypaper/config.ini"
readonly cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/self-shell"
readonly lock_background="$cache_dir/lockscreen-wallpaper.png"
readonly lock_state="$cache_dir/lockscreen-wallpaper.state"
readonly fallback="$HOME/.local/share/self-shell/wallpapers/wallpeper.jpg"

current_wallpaper() {
  local wallpaper
  wallpaper="$(awk -F' = ' '$1 == "wallpaper" { print $2; exit }' "$waypaper_config" 2>/dev/null || true)"
  wallpaper="${wallpaper/#\~/$HOME}"
  if [[ -f "$wallpaper" ]]; then printf '%s\n' "$wallpaper"; else printf '%s\n' "$fallback"; fi
}

prepare_background() {
  local wallpaper signature temporary extension
  wallpaper="$(current_wallpaper)"
  [[ -f "$wallpaper" ]] || return 1
  signature="$wallpaper:$(stat -c '%Y:%s' "$wallpaper")"
  if [[ -s "$lock_background" && -r "$lock_state" && "$(<"$lock_state")" == "$signature" ]]; then
    return 0
  fi

  mkdir -p "$cache_dir"
  temporary="$(mktemp "$cache_dir/lockscreen-wallpaper.XXXXXX.png")"
  trap 'rm -f -- "${temporary:-}"' RETURN
  extension="${wallpaper##*.}"
  case "${extension,,}" in
    mp4|mkv|webm|mov|m4v|avi)
      ffmpeg -hide_banner -loglevel error -y -ss 00:00:01 -i "$wallpaper" -frames:v 1 "$temporary"
      ;;
    *)
      magick "${wallpaper}[0]" -auto-orient "$temporary"
      ;;
  esac
  mv -f -- "$temporary" "$lock_background"
  printf '%s\n' "$signature" > "$lock_state"
  trap - RETURN
}

lock_in_english() {
  local previous_layout previous_index=0
  previous_layout="$(hyprctl -j devices 2>/dev/null | jq -r '.keyboards[] | select(.main == true) | .active_keymap' | head -n 1 || true)"
  [[ "${previous_layout,,}" == *russian* ]] && previous_index=1

  restore_layout() {
    local layout_index="${1:-0}"
    hyprctl keyword input:kb_layout 'us,ru' >/dev/null 2>&1 || true
    hyprctl switchxkblayout all "$layout_index" >/dev/null 2>&1 || true
  }
  trap "restore_layout $previous_index" EXIT INT TERM

  # One available layout prevents accidental switching to Russian while locked.
  hyprctl keyword input:kb_layout us >/dev/null
  hyprlock
}

command -v hyprlock >/dev/null 2>&1 || {
  notify-send "Блокировка" "Hyprlock не установлен"
  exit 1
}

prepare_background || notify-send "Блокировка" "Не удалось подготовить текущие обои"
lock_in_english
