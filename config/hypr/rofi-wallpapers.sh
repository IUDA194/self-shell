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
readonly live_wallpaper_dir="$wallpaper_dir/live"
readonly theme_state="${XDG_CONFIG_HOME:-$HOME/.config}/self-shell/wallpaper-themes.json"
readonly text_theme_state="${XDG_CONFIG_HOME:-$HOME/.config}/self-shell/wallpaper-text-themes.json"
readonly text_custom_state="${XDG_CONFIG_HOME:-$HOME/.config}/self-shell/wallpaper-text-colors.json"
readonly palette_cache="$cache_dir/palettes"
readonly active_palette="${XDG_CACHE_HOME:-$HOME/.cache}/self-shell/active-palette.json"
readonly mpvpaper_socket="${XDG_RUNTIME_DIR:-/tmp}/self-shell-mpvpaper.sock"

theme_for_wallpaper() {
  local path="$1"
  local interface_state="${XDG_CONFIG_HOME:-$HOME/.config}/self-shell/interface-style.json" mode fixed
  mode="$(jq -r '.colorMode // "wallpaper"' "$interface_state" 2>/dev/null || printf wallpaper)"
  if [[ "$mode" == "fixed" ]]; then
    fixed="$(jq -r '.fixedScheme // "default"' "$interface_state" 2>/dev/null || printf default)"
    printf '%s\n' "$fixed"
    return
  fi
  printf 'auto\n'
}

set_color_mode() {
  local mode="$1" scheme="${2:-default}" state_file="${XDG_CONFIG_HOME:-$HOME/.config}/self-shell/interface-style.json" state_tmp current
  case "$mode" in wallpaper) scheme="default" ;; fixed) case "$scheme" in default|kanagawa|gruvbox|nord|paper|solarized-light|latte|rose-dawn|dracula|tokyo-night|one-light|github-light|everforest-light|ayu-light|iceberg|monokai|custom) ;; *) return 2 ;; esac ;; *) return 2 ;; esac
  mkdir -p "${state_file%/*}"
  state_tmp="$(mktemp "${state_file%/*}/interface-style.XXXXXX")"
  if [[ -s "$state_file" ]]; then
    jq --arg mode "$mode" --arg scheme "$scheme" '.colorMode=$mode | .fixedScheme=$scheme' "$state_file" > "$state_tmp"
  else
    jq -cn --arg mode "$mode" --arg scheme "$scheme" '{style:"modern",panelPosition:"left",colorMode:$mode,fixedScheme:$scheme,opacity:0.94}' > "$state_tmp"
  fi
  mv -- "$state_tmp" "$state_file"
  current="$(awk -F' = ' '$1 == "wallpaper" { print $2; exit }' "$HOME/.config/waypaper/config.ini" 2>/dev/null || true)"
  [[ -z "$current" ]] || activate_palette "$current"
  build_manifest
}

set_custom_interface_color() {
  local color="${1,,}" state_file="${XDG_CONFIG_HOME:-$HOME/.config}/self-shell/interface-style.json" state_tmp
  [[ "$color" =~ ^#[[:xdigit:]]{6}$ ]] || return 2
  mkdir -p "${state_file%/*}"
  state_tmp="$(mktemp "${state_file%/*}/interface-style.XXXXXX")"
  if [[ -s "$state_file" ]]; then
    jq --arg color "$color" '.colorMode="fixed" | .fixedScheme="custom" | .customColor=$color' "$state_file" > "$state_tmp"
  else
    jq -cn --arg color "$color" '{style:"modern",panelPosition:"left",colorMode:"fixed",fixedScheme:"custom",customColor:$color,opacity:0.94}' > "$state_tmp"
  fi
  mv -- "$state_tmp" "$state_file"
  set_color_mode fixed custom
}

text_theme_for_wallpaper() {
  local path="$1"
  [[ -s "$text_theme_state" ]] || { printf 'obsidian\n'; return; }
  jq -r --arg path "$path" '.[$path] // "obsidian"' "$text_theme_state" 2>/dev/null || printf 'obsidian\n'
}

text_custom_color_for_wallpaper() {
  local path="$1"
  jq -r --arg path "$path" '.[$path] // "#b58e66"' "$text_custom_state" 2>/dev/null || printf '#b58e66\n'
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
  local theme="$1" source="$2" base saturation key cache_file
  case "$theme" in
    custom)
      base="$(jq -r '.customColor // "#b58e66"' "${XDG_CONFIG_HOME:-$HOME/.config}/self-shell/interface-style.json" 2>/dev/null || printf '#b58e66')"
      [[ "$base" =~ ^#[[:xdigit:]]{6}$ ]] || base='#b58e66'
      write_palette custom "$(hsl_color "$base" 34 12)" "$(hsl_color "$base" 30 18)" \
        "$(hsl_color "$base" 32 26)" "$(hsl_color "$base" 38 40)" \
        "$(hsl_color "$base" 18 88)" "$(hsl_color "$base" 20 78)" \
        "$(hsl_color "$base" 18 58)" "$(hsl_color "$base" 62 60)" \
        "$(hsl_color "$base" 68 68)" "$(hsl_color "$base" 28 10)" '#c4746e' '#8aa08a'
      ;;
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
    paper)
      write_palette paper '#fafafa' '#f2f2f2' '#e3e3e3' '#d5e3ff' '#202124' '#34373b' '#6b7078' '#3366cc' '#2457b8' '#ffffff' '#c62828' '#2e7d32'
      ;;
    solarized-light)
      write_palette solarized-light '#fdf6e3' '#f5efdc' '#eee8d5' '#d9e7e8' '#073642' '#425b62' '#839496' '#268bd2' '#1675b8' '#ffffff' '#dc322f' '#859900'
      ;;
    latte)
      write_palette latte '#eff1f5' '#e6e9ef' '#dce0e8' '#ccd8f4' '#4c4f69' '#5c5f77' '#8c8fa1' '#1e66f5' '#1757d1' '#ffffff' '#d20f39' '#40a02b'
      ;;
    rose-dawn)
      write_palette rose-dawn '#faf4ed' '#fffaf3' '#f2e9e1' '#dfdad9' '#575279' '#6e6a86' '#9893a5' '#907aa9' '#7f669c' '#ffffff' '#b4637a' '#56949f'
      ;;
    dracula)
      write_palette dracula '#282a36' '#343746' '#44475a' '#565a70' '#f8f8f2' '#dedee8' '#8b90a7' '#bd93f9' '#caa8ff' '#282a36' '#ff5555' '#50fa7b'
      ;;
    tokyo-night)
      write_palette tokyo-night '#1a1b26' '#202330' '#292e42' '#3b4261' '#c0caf5' '#a9b1d6' '#737aa2' '#7aa2f7' '#89b4fa' '#1a1b26' '#f7768e' '#9ece6a'
      ;;
    one-light)
      write_palette one-light '#fafafa' '#f3f3f3' '#e5e5e6' '#dbe4fa' '#383a42' '#4f525d' '#8a8d98' '#4078f2' '#2f65d6' '#ffffff' '#e45649' '#50a14f'
      ;;
    github-light)
      write_palette github-light '#ffffff' '#f6f8fa' '#d8dee4' '#ddf4ff' '#24292f' '#424a53' '#6e7781' '#0969da' '#0557b7' '#ffffff' '#cf222e' '#1a7f37'
      ;;
    everforest-light)
      write_palette everforest-light '#fdf6e3' '#f4f0d9' '#e8e5d5' '#e0e4c1' '#5c6a72' '#6f7b80' '#939f91' '#8da101' '#7a8c00' '#ffffff' '#f85552' '#35a77c'
      ;;
    ayu-light)
      write_palette ayu-light '#fafafa' '#f3f4f5' '#e7e8e9' '#fff0dc' '#5c6166' '#6c737a' '#92989d' '#ff9940' '#e67e22' '#332b22' '#f07171' '#86b300'
      ;;
    iceberg)
      write_palette iceberg '#161821' '#1e2132' '#2e313f' '#3e445e' '#c6c8d1' '#a8abb8' '#6b7089' '#84a0c6' '#91acd1' '#161821' '#e27878' '#b4be82'
      ;;
    monokai)
      write_palette monokai '#272822' '#35362f' '#49483e' '#5b594c' '#f8f8f2' '#d6d6ce' '#90908a' '#a6e22e' '#b8f23c' '#272822' '#f92672' '#66d9ef'
      ;;
    auto|*)
      mkdir -p "$palette_cache"
      # Keep the algorithm version in the key so palette fixes also refresh
      # already generated video thumbnails.
      key="$(printf 'v3:%s:%s' "$source" "$(stat -c %Y "$source" 2>/dev/null || printf 0)" | sha256sum | cut -d' ' -f1)"
      cache_file="$palette_cache/$key.json"
      if [[ ! -s "$cache_file" ]]; then
        base="$(magick "${source}[0]" -auto-orient -resize 1x1! -colorspace sRGB \
          -format '%[hex:p{0,0}]' info: 2>/dev/null || true)"
        base="#${base:0:6}"
        [[ "$base" =~ ^#[[:xdigit:]]{6}$ ]] || base='#b58e66'
        saturation="$(magick "xc:$base" -colorspace HSL -format '%[fx:mean.g*100]' info: 2>/dev/null || printf 100)"
        if awk -v value="$saturation" 'BEGIN { exit !(value < 8) }'; then
          # Grayscale and near-white images have no meaningful hue. Boosting
          # their saturation invents a random (often red) accent, so keep the
          # complete interface neutral instead.
          write_palette auto '#17191c' '#202328' '#2b2f35' '#424850' \
            '#f1f2f3' '#d7d9dc' '#92979e' '#aeb4bc' '#c4c9cf' '#17191c' \
            '#c4746e' '#8aa08a' > "$cache_file"
        else
          write_palette auto \
            "$(hsl_color "$base" 34 12)" "$(hsl_color "$base" 30 18)" \
            "$(hsl_color "$base" 32 26)" "$(hsl_color "$base" 38 40)" \
            "$(hsl_color "$base" 18 88)" "$(hsl_color "$base" 20 78)" \
            "$(hsl_color "$base" 18 58)" "$(hsl_color "$base" 62 60)" \
            "$(hsl_color "$base" 68 68)" "$(hsl_color "$base" 28 10)" \
            '#c4746e' '#8aa08a' > "$cache_file"
        fi
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
  "$HOME/.config/hypr/apply-text-theme.sh" "$text_theme" "$active_palette" "$(text_custom_color_for_wallpaper "$path")" || true
}

set_wallpaper_theme() {
  local path="$1" theme="$2" state_tmp current
  case "$theme" in auto|default|kanagawa|gruvbox|nord|paper|solarized-light|latte|rose-dawn|dracula|tokyo-night|one-light|github-light|everforest-light|ayu-light|iceberg|monokai) ;; *) return 2 ;; esac
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
  case "$text_theme" in auto|obsidian|kanagawa|gruvbox|nord|custom) ;; *) return 2 ;; esac
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
    "$HOME/.config/hypr/apply-text-theme.sh" "$text_theme" "$active_palette" "$(text_custom_color_for_wallpaper "$path")" || true
  fi
}

set_custom_text_color() {
  local path="$1" color="${2,,}" state_tmp
  [[ "$color" =~ ^#[[:xdigit:]]{6}$ ]] || return 2
  mkdir -p "${text_custom_state%/*}"
  state_tmp="$(mktemp "${text_custom_state}.XXXXXX")"
  if [[ -s "$text_custom_state" ]]; then
    jq --arg path "$path" --arg color "$color" '.[$path]=$color' "$text_custom_state" > "$state_tmp"
  else
    jq -cn --arg path "$path" --arg color "$color" '{($path):$color}' > "$state_tmp"
  fi
  mv -- "$state_tmp" "$text_custom_state"
  set_wallpaper_text_theme "$path" custom
  build_manifest
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

mpvpaper_ipc() {
  local payload="$1"
  printf '%s\n' "$payload" | nc -N -U -w 2 "$mpvpaper_socket" 2>/dev/null
}

switch_mpvpaper() {
  local path="$1"
  mpvpaper_ipc "$(jq -cn --arg path "$path" \
    '{command:["loadfile",$path,"replace"]}')" >/dev/null
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
    command -v mpvpaper >/dev/null 2>&1 || {
      notify-send "Обои" "mpvpaper не установлен"
      return 1
    }

    # Keep the existing Wayland surface alive when switching live wallpapers.
    # mpv retains the old frame until the replacement file is ready, so the
    # static awww layer underneath never flashes between two videos.
    if [[ -S "$mpvpaper_socket" ]] && pgrep -x mpvpaper >/dev/null 2>&1 \
        && switch_mpvpaper "$path"; then
      :
    else
      pkill -x mpvpaper 2>/dev/null || true
      rm -f -- "$mpvpaper_socket"
      mpvpaper --fork --auto-stop \
        --mpv-options "no-audio loop-file=inf keep-open=yes hwdec=nvdec input-ipc-server=$mpvpaper_socket" \
        '*' "$path" >/dev/null 2>&1
    fi
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
  local output_tmp path name preview kind group theme text_theme accent palette added_at first=true

  mkdir -p "$thumb_dir"
  output_tmp="$(mktemp "$cache_dir/manifest.XXXXXX")"
  trap 'rm -f "${output_tmp:-}"' RETURN

  printf '[' > "$output_tmp"
  while IFS= read -r -d '' path; do
    name="$(basename "$path")"
    preview="$path"
    kind="image"
    group="static"

    if [[ "$path" == "$live_wallpaper_dir/"* ]]; then
      group="live"
    fi

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
    added_at="$(stat -c %W "$path" 2>/dev/null || printf 0)"
    if [[ ! "$added_at" =~ ^[0-9]+$ || "$added_at" -le 0 ]]; then
      added_at="$(stat -c %Y "$path" 2>/dev/null || printf 0)"
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
      --arg group "$group" \
      --arg theme "$theme" \
      --arg textTheme "$text_theme" \
      --arg accent "$accent" \
      --argjson addedAt "$added_at" \
      '{path: $path, preview: $preview, name: $name, kind: $kind, group: $group, scheme: $theme, textTheme: $textTheme, accent: $accent, addedAt: $addedAt}' \
      >> "$output_tmp"
  done < <(
    {
      find "$wallpaper_dir" -maxdepth 1 -type f -print0
      [[ ! -d "$live_wallpaper_dir" ]] || find "$live_wallpaper_dir" -maxdepth 1 -type f -print0
    } | while IFS= read -r -d '' path; do
      case "${path##*.}" in
        [jJ][pP][gG]|[jJ][pP][eE][gG]|[pP][nN][gG]|[wW][eE][bB][pP]|[gG][iI][fF]|[mM][pP]4|[mM][kK][vV]|[wW][eE][bB][mM]|[mM][oO][vV]|[mM]4[vV]|[aA][vV][iI]) printf '%s\0' "$path" ;;
      esac
    done | sort -z
  )
  printf ']\n' >> "$output_tmp"

  mv "$output_tmp" "$manifest"
  trap - RETURN
}

manifest_is_fresh() {
  [[ -s "$manifest" ]] || return 1
  jq -e 'length == 0 or (.[0] | has("group") and has("scheme") and has("textTheme") and has("accent") and has("addedAt"))' "$manifest" >/dev/null 2>&1 || return 1
  [[ "$wallpaper_dir" -ot "$manifest" ]] || return 1
  [[ ! -d "$live_wallpaper_dir" || "$live_wallpaper_dir" -ot "$manifest" ]] || return 1
  [[ -z "$(find "$wallpaper_dir" -maxdepth 1 -type f -newer "$manifest" -print -quit)" ]] || return 1
  [[ ! -d "$live_wallpaper_dir" || -z "$(find "$live_wallpaper_dir" -maxdepth 1 -type f -newer "$manifest" -print -quit)" ]]
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

if [[ "${1:-}" == "--set-color-mode" ]]; then
  [[ $# -ge 2 ]] || exit 2
  set_color_mode "$2" "${3:-default}"
  exit
fi

if [[ "${1:-}" == "--set-custom-color" ]]; then
  [[ $# -eq 2 ]] || exit 2
  set_custom_interface_color "$2"
  exit
fi

if [[ "${1:-}" == "--set-custom-text-color" ]]; then
  [[ $# -eq 3 && -f "$2" ]] || exit 2
  set_custom_text_color "$2" "$3"
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
