#!/usr/bin/fish

# Obsidian warm palette aligned with Waybar and obsidian-page-render
set -l foreground CCC2B7 normal
set -l muted ADA59C brblack
set -l soft 8F847A brblack
set -l faint 746961 brblack
set -l red 9F7D52 red
set -l orange BA945F brred
set -l yellow 9D7B52 yellow
set -l green ADA59C green
set -l purple B9A4B8 magenta
set -l cyan CCC2B7 cyan
set -l selection 685D58 brblack

# Syntax highlighting
set -g fish_color_normal $foreground
set -g fish_color_command $yellow
set -g fish_color_keyword $orange
set -g fish_color_quote $foreground
set -g fish_color_redirection $muted
set -g fish_color_end $orange
set -g fish_color_error $red
set -g fish_color_param $cyan
set -g fish_color_comment $faint
set -g fish_color_selection --background=$selection
set -g fish_color_search_match --background=$selection
set -g fish_color_operator $muted
set -g fish_color_escape $orange
set -g fish_color_autosuggestion $faint
set -g fish_color_valid_path $muted
set -g fish_color_option $muted
set -g fish_color_cwd $orange
set -g fish_color_cwd_root $red
set -g fish_color_user $cyan
set -g fish_color_host $muted
set -g fish_color_host_remote $orange
set -g fish_color_cancel $red

# Completion pager
set -g fish_pager_color_progress $faint
set -g fish_pager_color_prefix $yellow
set -g fish_pager_color_completion $foreground
set -g fish_pager_color_description $muted
set -g fish_pager_color_selected_background --background=$selection

# Tide prompt
set -g tide_left_prompt_items pwd git newline character
set -g tide_right_prompt_items
set -g tide_os_icon_display no

# Tide stores many settings as universal vars, so set them here explicitly
set -U tide_character_icon '~>'
set -U tide_character_vi_icon_default '~>'
set -U tide_character_vi_icon_replace '~>'
set -U tide_character_vi_icon_visual '~>'
set -U tide_character_vi_icon_insert '~>'

set -U tide_pwd_color_dirs 9D7B52
set -U tide_pwd_color_anchors BA945F
set -U tide_pwd_color_truncated_dirs 8F847A
set -U tide_pwd_icon ""
set -U tide_pwd_icon_home ""
set -U tide_pwd_icon_unanchored ""

set -U tide_character_color BA945F
set -U tide_character_color_failure 9F7D52

set -U tide_git_icon ""
set -U tide_git_color_branch BA945F
set -U tide_git_color_dirty 9D7B52
set -U tide_git_color_untracked ADA59C
set -U tide_git_color_staged CCC2B7
set -U tide_git_color_upstream 8F847A
set -U tide_git_color_operation 9F7D52
set -U tide_git_color_conflicted 9F7D52
set -U tide_git_color_stash CCC2B7

set -g tide_left_prompt_frame_enabled false
set -g tide_right_prompt_frame_enabled false

# LS_COLORS in the same palette
# Directories get the warm amber accent so they stand out from regular files.
set -gx LS_COLORS "di=1;38;2;186;148;95:ex=38;2;159;125;82:ln=38;2;185;164;184:or=38;2;159;125;82:so=38;2;186;148;95:pi=38;2;173;165;156:bd=38;2;204;194;183:cd=38;2;204;194;183:fi=38;2;204;194;183"
