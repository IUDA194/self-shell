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
tmux_theme="$cache_dir/tmux-theme.conf"
mkdir -p "$cache_dir"
tmux_theme_tmp="$(mktemp "${tmux_theme}.XXXXXX")"
cat > "$tmux_theme_tmp" <<EOF
# Generated from the active wallpaper palette. Do not edit.
set -g status-style "bg=default,fg=#$foreground"
set -g message-style "bg=default,fg=#$foreground"
set -g message-command-style "bg=default,fg=#$foreground"
set -g pane-border-style "fg=#$surface_alt"
set -g pane-active-border-style "fg=#$accent"
set -g window-status-style "fg=#$muted,bg=default"
set -g window-status-current-style "fg=#$accent,bg=default,bold"
set -g window-status-activity-style "fg=#$accent_hover,bg=default,bold"
set -g window-status-bell-style "fg=#$accent_hover,bg=default,bold"
set -g window-status-format "#[fg=#$muted,bg=default] #I:#W "
set -g window-status-current-format "#[fg=#$accent,bg=default,bold] #I:#W "
set -g status-left-style "fg=#$accent,bg=default"
set -g status-right-style "fg=#$foreground_soft,bg=default"
set -g status-left '#[fg=#$accent,bold] #S '
set -g status-right '#(~/.local/bin/tmux-state-save >/dev/null 2>&1)#[fg=#$foreground_soft]%Y-%m-%d #[fg=#$surface_alt]| #[fg=#$foreground,bold]%H:%M '
set -g mode-style "bg=#$surface,fg=#$foreground"
set -g clock-mode-colour "#$accent"
EOF
mv -- "$tmux_theme_tmp" "$tmux_theme"

if command -v tmux >/dev/null 2>&1 && tmux list-sessions >/dev/null 2>&1; then
  tmux source-file "$tmux_theme"
fi

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
