#!/usr/bin/env bash

set -euo pipefail

export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$PATH"
export AWWW_TRANSITION_WAVE="64,22"
export AWWW_TRANSITION_BEZIER=".22,.72,.20,1"

readonly picker_dir="$HOME/.config/hypr/wallpaper-picker"
readonly cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/hypr-wallpapers"
readonly thumb_dir="$cache_dir/thumbs"
readonly manifest="$cache_dir/manifest.json"
readonly wallpaper_dir="$HOME/Documents/Wallpapers"

is_video_file() {
  local extension="${1##*.}"
  case "${extension,,}" in
    mp4|mkv|webm|mov|m4v|avi) return 0 ;;
    *) return 1 ;;
  esac
}

is_gif_file() {
  local extension="${1##*.}"
  [[ "${extension,,}" == "gif" ]]
}

video_thumbnail() {
  local path="$1"
  local key thumb

  key="$(printf '%s' "$path" | sha256sum | cut -d' ' -f1)"
  thumb="$thumb_dir/$key.jpg"

  if [[ ! -f "$thumb" || "$path" -nt "$thumb" ]]; then
    if ! ffmpeg -hide_banner -loglevel error -y -ss 00:00:01 -i "$path" \
      -frames:v 1 -vf 'scale=640:360:force_original_aspect_ratio=increase,crop=640:360' \
      "$thumb" >/dev/null 2>&1; then
      printf '%s\n' "$path"
      return 0
    fi
  fi

  printf '%s\n' "$thumb"
}

apply_wallpaper() {
  local path="$1"
  local backend="awww"

  [[ -f "$path" ]] || {
    notify-send "Обои" "Файл не найден: $path"
    return 1
  }

  if is_video_file "$path"; then
    backend="mpvpaper"
  fi

  # Wallpaper Engine из обычной сессии не должен перекрывать выбранные обои.
  pkill -f '/linux-wallpaperengine([[:space:]]|$)' 2>/dev/null || true

  if [[ "$backend" == "awww" ]]; then
    pkill -x mpvpaper 2>/dev/null || true
    if ! awww query >/dev/null 2>&1; then
      awww-daemon >/dev/null 2>&1 &
      sleep 0.3
    fi
    awww img "$path" \
      --transition-type wave \
      --transition-duration 1.45 \
      --transition-fps 120 \
      --transition-angle 18
  else
    # Restart mpvpaper so GIF/video loop options are applied consistently.
    pkill -x mpvpaper 2>/dev/null || true
    command -v mpvpaper >/dev/null 2>&1 || {
      notify-send "Обои" "mpvpaper не установлен"
      return 1
    }
    mpvpaper --fork --auto-stop --mpv-options "no-audio loop-file=inf keep-open=yes" \
      '*' "$path" >/dev/null 2>&1
  fi

  local settings="$HOME/.config/waypaper/config.ini" settings_tmp
  if [[ -f "$settings" ]]; then
    settings_tmp="$(mktemp "${settings}.XXXXXX")"
    awk -v wallpaper="$path" '
      /^wallpaper[[:space:]]*=/ { print "wallpaper = " wallpaper; found=1; next }
      { print }
      END { if (!found) print "wallpaper = " wallpaper }
    ' "$settings" > "$settings_tmp"
    mv -- "$settings_tmp" "$settings"
  fi
}

build_manifest() {
  local output_tmp path name preview kind first=true

  mkdir -p "$thumb_dir"
  output_tmp="$(mktemp "$cache_dir/manifest.XXXXXX")"
  trap 'rm -f "${output_tmp:-}"' RETURN

  printf '[' > "$output_tmp"
  while IFS= read -r -d '' path; do
    name="$(basename "$path")"
    preview="$path"
    kind="image"

    if is_video_file "$path"; then
      preview="$(video_thumbnail "$path")"
      kind="video"
    elif is_gif_file "$path"; then
      kind="gif"
    fi

    if [[ "$first" == true ]]; then
      first=false
    else
      printf ',' >> "$output_tmp"
    fi

    jq -cn \
      --arg path "$path" \
      --arg preview "$preview" \
      --arg name "$name" \
      --arg kind "$kind" \
      '{path: $path, preview: $preview, name: $name, kind: $kind}' \
      >> "$output_tmp"
  done < <(
    find "$wallpaper_dir" -maxdepth 1 -type f \
      \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \
         -o -iname '*.gif' -o -iname '*.mp4' -o -iname '*.mkv' -o -iname '*.webm' \
         -o -iname '*.mov' -o -iname '*.m4v' -o -iname '*.avi' \) \
      -print0 | sort -z
  )
  printf ']\n' >> "$output_tmp"

  mv "$output_tmp" "$manifest"
  trap - RETURN
}

manifest_is_fresh() {
  [[ -s "$manifest" ]] || return 1
  [[ "$wallpaper_dir" -ot "$manifest" ]] || return 1
  [[ -z "$(find "$wallpaper_dir" -maxdepth 1 -type f -newer "$manifest" -print -quit)" ]]
}

if [[ "${1:-}" == "--apply" ]]; then
  [[ $# -eq 2 ]] || exit 2
  apply_wallpaper "$2"
  exit
fi

command -v quickshell >/dev/null 2>&1 || {
  notify-send "Обои" "Quickshell не установлен"
  exit 1
}

[[ -d "$wallpaper_dir" ]] || {
  notify-send "Обои" "Папка не найдена: $wallpaper_dir"
  exit 1
}

if ! manifest_is_fresh; then
  build_manifest
fi

if [[ "$(jq 'length' "$manifest")" -eq 0 ]]; then
  notify-send "Обои" "В папке нет поддерживаемых файлов"
  exit 1
fi

if [[ "${1:-}" == "--prepare" ]]; then
  printf '%s\n' "$manifest"
  exit 0
fi

if [[ "${1:-}" == "--picker" ]]; then
  export WALLPAPER_PICKER_MANIFEST="$manifest"
  export WALLPAPER_PICKER_SCRIPT="$0"
  export WALLPAPER_PICKER_CURRENT="$(awk -F' = ' '$1 == "wallpaper" { print $2; exit }' "$HOME/.config/waypaper/config.ini" | sed "s#^~#$HOME#")"
  exec quickshell --no-duplicate --path "$picker_dir"
fi

"$HOME/.config/hypr/quickshell-launcher.sh" wallpaper
