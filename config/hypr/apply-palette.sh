#!/usr/bin/env bash

set -euo pipefail

palette_file="${1:-${XDG_CACHE_HOME:-$HOME/.cache}/self-shell/active-palette.json}"
[[ -s "$palette_file" ]] || exit 0

color() {
  jq -er --arg name "$1" '.colors[$name] // empty' "$palette_file" \
    | sed -E 's/^#//; y/ABCDEF/abcdef/'
}

accent="$(color accent)"
accent_hover="$(color accentHover)"
foreground="$(color foreground)"
foreground_soft="$(color foregroundSoft)"
muted="$(color muted)"
surface="$(color surface)"
surface_alt="$(color surfaceAlt)"

for value in "$accent" "$accent_hover" "$foreground" "$foreground_soft" \
    "$muted" "$surface" "$surface_alt"; do
  [[ "$value" =~ ^[0-9a-f]{6}$ ]] || exit 1
done

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/self-shell"
niri_palette="$cache_dir/niri-palette.kdl"
mkdir -p "$cache_dir"

# Niri reads this included file and reloads it automatically. Keep the
# border colors in sync with the wallpaper palette used by Hyprland and
# Quickshell.
niri_palette_tmp="$(mktemp "${niri_palette}.XXXXXX")"
printf '%s\n' \
  '// Generated from the active wallpaper palette. Do not edit.' \
  'layout {' \
  '    border {' \
  "        active-color \"#${accent}ee\"" \
  "        inactive-color \"#${surface_alt}99\"" \
  '    }' \
  '}' > "$niri_palette_tmp"
mv -- "$niri_palette_tmp" "$niri_palette"

# Hyprland expects RRGGBBAA in rgba(). Border transitions use its native
# `animation = border`, so they stay in sync with the Quickshell palette fade.
hyprctl --batch \
  "keyword general:col.active_border rgba(${accent}ee); \
   keyword general:col.inactive_border rgba(${surface_alt}99); \
   keyword group:col.border_active rgba(${accent_hover}ee); \
   keyword group:col.border_inactive rgba(${surface_alt}99); \
   keyword group:col.border_locked_active rgba(${accent}ee); \
   keyword group:col.border_locked_inactive rgba(${surface_alt}99)" \
  >/dev/null 2>&1 || true
