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
readonly theme_state="${XDG_CONFIG_HOME:-$HOME/.config}/self-shell/wallpaper-themes.json"
readonly text_theme_state="${XDG_CONFIG_HOME:-$HOME/.config}/self-shell/wallpaper-text-themes.json"
readonly palette_cache="$cache_dir/palettes"
readonly active_palette="${XDG_CACHE_HOME:-$HOME/.cache}/self-shell/active-palette.json"

theme_for_wallpaper() {
  local path="$1"
  [[ -s "$theme_state" ]] || { printf 'auto\n'; return; }
  jq -r --arg path "$path" '.[$path] // "auto"' "$theme_state" 2>/dev/null || printf 'auto\n'
}

text_theme_for_wallpaper() {
  local path="$1"
  [[ -s "$text_theme_state" ]] || { printf 'obsidian\n'; return; }
  jq -r --arg path "$path" '.[$path] // "obsidian"' "$text_theme_state" 2>/dev/null || printf 'obsidian\n'
}

hsl_color() {
  local source="$1" saturation="$2" lightness="$3" result
  result="$(magick "xc:$source" -colorspace HSL \
    -channel G -evaluate set "${saturation}%" -channel B -evaluate set "${lightness}%" \
    +channel -colorspace sRGB -depth 8 -format '%[hex:p{0,0}]' info: 2>/dev/null)"
  printf '#%s\n' "${result:0:6}"
}

write_palette() {
  local name="$1" background="$2" surface="$3" surface_alt="$4" selected="$5"
  local foreground="$6" foreground_soft="$7" muted="$8" accent="$9"
  local accent_hover="${10}" accent_foreground="${11}" critical="${12}" success="${13}"
  local outline="#b8${selected#\#}" scrim='#b3000000'
  jq -cn --arg name "$name" --arg background "$background" --arg surface "$surface" \
    --arg surfaceAlt "$surface_alt" --arg selected "$selected" --arg foreground "$foreground" \
    --arg foregroundSoft "$foreground_soft" --arg muted "$muted" --arg accent "$accent" \
    --arg accentHover "$accent_hover" --arg accentForeground "$accent_foreground" \
    --arg critical "$critical" --arg success "$success" --arg outline "$outline" --arg scrim "$scrim" \
    '{name:$name,colors:{background:$background,surface:$surface,surfaceAlt:$surfaceAlt,
      selected:$selected,foreground:$foreground,foregroundSoft:$foregroundSoft,muted:$muted,
      accent:$accent,accentHover:$accentHover,accentForeground:$accentForeground,
      critical:$critical,success:$success,outline:$outline,scrim:$scrim}}'
}

palette_for_theme() {
  local theme="$1" source="$2" base key cache_file
  case "$theme" in
    default)
      write_palette default '#26201d' '#372d29' '#4f443e' '#756054' '#ddd3c6' '#cfc5ba' '#9a8b80' '#b58e66' '#c29a6a' '#26201d' '#c4746e' '#8aa08a'
      ;;
    kanagawa)
      write_palette kanagawa '#1f1f28' '#2a2a37' '#363646' '#54546d' '#dcd7ba' '#c8c093' '#727169' '#c0a36e' '#e6c384' '#1f1f28' '#c34043' '#76946a'
      ;;
    gruvbox)
      write_palette gruvbox '#282828' '#3c3836' '#504945' '#665c54' '#ebdbb2' '#d5c4a1' '#928374' '#d79921' '#fabd2f' '#282828' '#cc241d' '#98971a'
      ;;
    nord)
      write_palette nord '#2e3440' '#3b4252' '#434c5e' '#4c566a' '#eceff4' '#e5e9f0' '#7b88a1' '#88c0d0' '#8fbcbb' '#2e3440' '#bf616a' '#a3be8c'
      ;;
    auto|*)
      mkdir -p "$palette_cache"
      key="$(printf 'v2:%s:%s' "$source" "$(stat -c %Y "$source" 2>/dev/null || printf 0)" | sha256sum | cut -d' ' -f1)"
      cache_file="$palette_cache/$key.json"
      if [[ ! -s "$cache_file" ]]; then
        base="$(magick "${source}[0]" -auto-orient -resize 1x1! -colorspace sRGB \
          -format '%[hex:p{0,0}]' info: 2>/dev/null || true)"
        base="#${base:0:6}"
        [[ "$base" =~ ^#[[:xdigit:]]{6}$ ]] || base='#b58e66'
        write_palette auto \
          "$(hsl_color "$base" 34 12)" "$(hsl_color "$base" 30 18)" \
          "$(hsl_color "$base" 32 26)" "$(hsl_color "$base" 38 40)" \
          "$(hsl_color "$base" 18 88)" "$(hsl_color "$base" 20 78)" \
          "$(hsl_color "$base" 18 58)" "$(hsl_color "$base" 62 60)" \
          "$(hsl_color "$base" 68 68)" "$(hsl_color "$base" 28 10)" \
          '#c4746e' '#8aa08a' > "$cache_file"
      fi
      cat "$cache_file"
      ;;
  esac
}

activate_palette() {
  local path="$1" theme text_theme palette_tmp palette_source="$1"
  theme="$(theme_for_wallpaper "$path")"
  if is_video_file "$path"; then
    palette_source="$(video_thumbnail "$path")"
  fi
  mkdir -p "$(dirname "$active_palette")"
  palette_tmp="$(mktemp "${active_palette}.XXXXXX")"
  palette_for_theme "$theme" "$palette_source" > "$palette_tmp"
  mv -- "$palette_tmp" "$active_palette"
  "$HOME/.config/hypr/apply-palette.sh" "$active_palette" || true
  text_theme="$(text_theme_for_wallpaper "$path")"
  "$HOME/.config/hypr/apply-text-theme.sh" "$text_theme" "$active_palette" || true
}

set_wallpaper_theme() {
  local path="$1" theme="$2" state_tmp current
  case "$theme" in auto|default|kanagawa|gruvbox|nord) ;; *) return 2 ;; esac
  mkdir -p "$(dirname "$theme_state")"
  state_tmp="$(mktemp "${theme_state}.XXXXXX")"
  if [[ -s "$theme_state" ]]; then
    jq --arg path "$path" --arg theme "$theme" '.[$path] = $theme' "$theme_state" > "$state_tmp"
  else
    jq -cn --arg path "$path" --arg theme "$theme" '{($path):$theme}' > "$state_tmp"
  fi
  mv -- "$state_tmp" "$theme_state"
  current="$(awk -F' = ' '$1 == "wallpaper" { print $2; exit }' "$HOME/.config/waypaper/config.ini" 2>/dev/null || true)"
  if [[ "$current" == "$path" ]]; then
    activate_palette "$path"
  fi
  return 0
}

set_wallpaper_text_theme() {
  local path="$1" text_theme="$2" state_tmp current
  case "$text_theme" in auto|obsidian|kanagawa|gruvbox|nord) ;; *) return 2 ;; esac
  mkdir -p "$(dirname "$text_theme_state")"
  state_tmp="$(mktemp "${text_theme_state}.XXXXXX")"
  if [[ -s "$text_theme_state" ]]; then
    jq --arg path "$path" --arg theme "$text_theme" '.[$path] = $theme' "$text_theme_state" > "$state_tmp"
  else
    jq -cn --arg path "$path" --arg theme "$text_theme" '{($path):$theme}' > "$state_tmp"
  fi
  mv -- "$state_tmp" "$text_theme_state"
  current="$(awk -F' = ' '$1 == "wallpaper" { print $2; exit }' "$HOME/.config/waypaper/config.ini" 2>/dev/null || true)"
  if [[ "$current" == "$path" ]]; then
    "$HOME/.config/hypr/apply-text-theme.sh" "$text_theme" "$active_palette" || true
  fi
}

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

  activate_palette "$path"

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
  local output_tmp path name preview kind theme text_theme accent palette first=true

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

    theme="$(theme_for_wallpaper "$path")"
    text_theme="$(text_theme_for_wallpaper "$path")"
    palette="$(palette_for_theme "$theme" "$preview")"
    accent="$(jq -r '.colors.accent' <<< "$palette")"

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
      --arg theme "$theme" \
      --arg textTheme "$text_theme" \
      --arg accent "$accent" \
      '{path: $path, preview: $preview, name: $name, kind: $kind, scheme: $theme, textTheme: $textTheme, accent: $accent}' \
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
  jq -e 'length == 0 or (.[0] | has("scheme") and has("textTheme") and has("accent"))' "$manifest" >/dev/null 2>&1 || return 1
  [[ "$wallpaper_dir" -ot "$manifest" ]] || return 1
  [[ -z "$(find "$wallpaper_dir" -maxdepth 1 -type f -newer "$manifest" -print -quit)" ]]
}

if [[ "${1:-}" == "--apply" ]]; then
  [[ $# -eq 2 ]] || exit 2
  apply_wallpaper "$2"
  exit
fi

if [[ "${1:-}" == "--set-theme" ]]; then
  [[ $# -eq 3 && -f "$2" ]] || exit 2
  set_wallpaper_theme "$2" "$3"
  build_manifest
  exit
fi

if [[ "${1:-}" == "--set-text-theme" ]]; then
  [[ $# -eq 3 && -f "$2" ]] || exit 2
  set_wallpaper_text_theme "$2" "$3"
  build_manifest
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
