#!/usr/bin/env bash

set -euo pipefail

theme="${1:-obsidian}"
palette_file="${2:-${XDG_CACHE_HOME:-$HOME/.cache}/self-shell/active-palette.json}"
custom_color="${3:-#b58e66}"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/self-shell"
text_palette="$cache_dir/text-theme.json"
fish_theme="$cache_dir/fish-text-theme.fish"
mkdir -p "$cache_dir"

hsl_color() {
  local source="$1" saturation="$2" lightness="$3" result
  result="$(magick "xc:$source" -colorspace HSL -channel G -evaluate set "${saturation}%" -channel B -evaluate set "${lightness}%" +channel -colorspace sRGB -depth 8 -format '%[hex:p{0,0}]' info: 2>/dev/null)"
  printf '#%s\n' "${result:0:6}"
}

case "$theme" in
  custom)
    [[ "$custom_color" =~ ^#[[:xdigit:]]{6}$ ]] || exit 2
    jq -cn --arg background "$(hsl_color "$custom_color" 30 12)" --arg surface "$(hsl_color "$custom_color" 28 18)" \
      --arg surfaceAlt "$(hsl_color "$custom_color" 30 26)" --arg selected "$(hsl_color "$custom_color" 36 38)" \
      --arg foreground "$(hsl_color "$custom_color" 18 90)" --arg foregroundSoft "$(hsl_color "$custom_color" 20 79)" \
      --arg muted "$(hsl_color "$custom_color" 18 58)" --arg accent "$(hsl_color "$custom_color" 68 66)" \
      --arg accentHover "$(hsl_color "$custom_color" 72 74)" \
      '{name:"custom",colors:{background:$background,surface:$surface,surfaceAlt:$surfaceAlt,selected:$selected,foreground:$foreground,foregroundSoft:$foregroundSoft,muted:$muted,accent:$accent,accentHover:$accentHover,critical:"#e06c75",success:"#98c379"}}' > "${text_palette}.tmp"
    ;;
  auto)
    jq -c '{name:"auto",colors:.colors}' "$palette_file" > "${text_palette}.tmp"
    ;;
  obsidian)
    jq -cn '{name:"obsidian",colors:{background:"#26201d",surface:"#372d29",surfaceAlt:"#4f443e",selected:"#685d58",foreground:"#ccc2b7",foregroundSoft:"#ada59c",muted:"#746961",accent:"#ba945f",accentHover:"#9d7b52",critical:"#9f7d52",success:"#ada59c"}}' > "${text_palette}.tmp"
    ;;
  kanagawa)
    jq -cn '{name:"kanagawa",colors:{background:"#1f1f28",surface:"#2a2a37",surfaceAlt:"#363646",selected:"#54546d",foreground:"#f2ecce",foregroundSoft:"#dcd7ba",muted:"#938aa9",accent:"#e6c384",accentHover:"#7fb4ca",critical:"#e46876",success:"#98bb6c"}}' > "${text_palette}.tmp"
    ;;
  gruvbox)
    jq -cn '{name:"gruvbox",colors:{background:"#282828",surface:"#3c3836",surfaceAlt:"#504945",selected:"#665c54",foreground:"#fbf1c7",foregroundSoft:"#ebdbb2",muted:"#bdae93",accent:"#fabd2f",accentHover:"#8ec07c",critical:"#fb4934",success:"#b8bb26"}}' > "${text_palette}.tmp"
    ;;
  nord)
    jq -cn '{name:"nord",colors:{background:"#2e3440",surface:"#3b4252",surfaceAlt:"#434c5e",selected:"#4c566a",foreground:"#ffffff",foregroundSoft:"#eceff4",muted:"#aebaca",accent:"#8fdaec",accentHover:"#a3d5ee",critical:"#ef8290",success:"#b8d49c"}}' > "${text_palette}.tmp"
    ;;
  rose-pine-moon)
    jq -cn '{name:"rose-pine-moon",colors:{background:"#232136",surface:"#2a273f",surfaceAlt:"#393552",selected:"#44415a",foreground:"#e0def4",foregroundSoft:"#c4a7e7",muted:"#908caa",accent:"#c4a7e7",accentHover:"#9ccfd8",critical:"#eb6f92",success:"#9ccfd8"}}' > "${text_palette}.tmp"
    ;;
  everforest-dark)
    jq -cn '{name:"everforest-dark",colors:{background:"#2b3339",surface:"#323c41",surfaceAlt:"#3a454a",selected:"#4f5b58",foreground:"#d3c6aa",foregroundSoft:"#9da9a0",muted:"#859289",accent:"#a7c080",accentHover:"#83c092",critical:"#e67e80",success:"#a7c080"}}' > "${text_palette}.tmp"
    ;;
  *) exit 2 ;;
esac
mv -- "${text_palette}.tmp" "$text_palette"

soften_color() {
  local hex="${1#\#}" red green blue gray
  [[ "$hex" =~ ^[[:xdigit:]]{6}$ ]] || exit 2
  red=$((16#${hex:0:2}))
  green=$((16#${hex:2:2}))
  blue=$((16#${hex:4:2}))
  gray=$(((red * 30 + green * 59 + blue * 11) / 100))
  red=$(((red * 65 + gray * 35 + 50) / 100))
  green=$(((green * 65 + gray * 35 + 50) / 100))
  blue=$(((blue * 65 + gray * 35 + 50) / 100))
  printf '#%02x%02x%02x\n' "$red" "$green" "$blue"
}

# Tone down the colors that draw attention. The backgrounds and text remain
# untouched, preserving readability and each theme's intended contrast.
for color_key in accent accentHover critical success; do
  original_color="$(jq -r --arg key "$color_key" '.colors[$key]' "$text_palette")"
  softened_color="$(soften_color "$original_color")"
  jq --arg key "$color_key" --arg color "$softened_color" '.colors[$key] = $color' "$text_palette" > "${text_palette}.tmp"
  mv -- "${text_palette}.tmp" "$text_palette"
done

# Keep terminal syntax and the prompt focused on one accent. Red is reserved
# for errors, so a command line does not turn into a rainbow of state colors.
jq '.colors.accentHover = .colors.accent | .colors.success = .colors.accent' "$text_palette" > "${text_palette}.tmp"
mv -- "${text_palette}.tmp" "$text_palette"

value() { jq -r --arg key "$1" '.colors[$key]' "$text_palette" | sed 's/^#//'; }
foreground="$(value foreground)"
foreground_soft="$(value foregroundSoft)"
muted="$(value muted)"
selected="$(value selected)"
accent="$(value accent)"
accent_hover="$(value accentHover)"
critical="$(value critical)"
success="$(value success)"
rgb() { printf '%d;%d;%d' "0x${1:0:2}" "0x${1:2:2}" "0x${1:4:2}"; }
foreground_rgb="$(rgb "$foreground")"
foreground_soft_rgb="$(rgb "$foreground_soft")"
accent_rgb="$(rgb "$accent")"
accent_hover_rgb="$(rgb "$accent_hover")"
critical_rgb="$(rgb "$critical")"
success_rgb="$(rgb "$success")"

cat > "${fish_theme}.tmp" <<EOF
# Generated from the wallpaper text theme. Do not edit.
set -g fish_color_normal $foreground
set -g fish_color_command $accent_hover --bold
set -g fish_color_keyword $accent --bold
set -g fish_color_quote $success
set -g fish_color_redirection $foreground_soft
set -g fish_color_end $accent
set -g fish_color_error $critical
set -g fish_color_param $foreground_soft
set -g fish_color_comment $muted
set -g fish_color_selection --background=$selected
set -g fish_color_search_match --background=$selected
set -g fish_color_operator $accent_hover
set -g fish_color_escape $accent
set -g fish_color_autosuggestion $muted
set -g fish_color_valid_path $foreground_soft
set -g fish_color_option $accent_hover
set -g fish_pager_color_progress $muted
set -g fish_pager_color_prefix $accent_hover
set -g fish_pager_color_completion $foreground
set -g fish_pager_color_description $muted
set -U tide_pwd_color_dirs $accent_hover
set -U tide_pwd_color_anchors $accent
set -U tide_pwd_color_truncated_dirs $muted
# Keep the prompt marker maximally visible over transparent terminals.
set -U tide_character_color $accent --bold
set -U tide_character_color_failure $critical --bold
set -U tide_git_color_branch $accent_hover
set -U tide_git_color_dirty $accent
set -U tide_git_color_untracked $muted
set -U tide_git_color_staged $foreground_soft
set -U tide_git_color_upstream $muted
set -U tide_git_color_operation $critical
set -U tide_git_color_conflicted $critical
set -U tide_git_color_stash $foreground_soft
set -gx LS_COLORS "di=1;38;2;$accent_rgb:ex=1;38;2;$success_rgb:ln=38;2;$accent_hover_rgb:or=1;38;2;$critical_rgb:so=38;2;$accent_hover_rgb:pi=38;2;$foreground_soft_rgb:fi=38;2;$foreground_rgb"
EOF
mv -- "${fish_theme}.tmp" "$fish_theme"

# Tide reads these colors from universal Fish variables. Apply them in a
# short-lived Fish process so already open shells receive the change too.
if command -v fish >/dev/null 2>&1; then
  fish -c "source '$fish_theme'" >/dev/null 2>&1 || true
fi

# Tmux is part of the terminal text theme, so it must follow this palette
# instead of the less contrasty desktop surface colors.
tmux_theme="$cache_dir/tmux-theme.conf"
cat > "${tmux_theme}.tmp" <<EOF
# Generated from the active text theme. Do not edit.
set -g status-style "bg=default,fg=#$foreground"
set -g pane-border-style "fg=#$muted"
set -g pane-active-border-style "fg=#$accent"
set -g window-status-style "fg=#$foreground_soft,bg=default"
set -g window-status-current-style "fg=#$accent,bg=default,bold"
set -g window-status-format "#[fg=#$foreground_soft,bg=default] #I:#W "
set -g window-status-current-format "#[fg=#$accent,bg=default,bold] #I:#W "
set -g status-left '#[fg=#$accent,bold] #S '
set -g status-right '#[fg=#$foreground_soft]%Y-%m-%d #[fg=#$muted]| #[fg=#$foreground,bold]%H:%M '
set -g mode-style "bg=#$selected,fg=#$foreground,bold"
set -g clock-mode-colour "#$accent"
EOF
mv -- "${tmux_theme}.tmp" "$tmux_theme"
if command -v tmux >/dev/null 2>&1 && tmux list-sessions >/dev/null 2>&1; then
  tmux source-file "$tmux_theme"
fi
