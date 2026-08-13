#!/usr/bin/fish

# Kanagawa Fish shell theme
# A template was taken and modified from Tokyonight:
# https://github.com/folke/tokyonight.nvim/blob/main/extras/fish_tokyonight_night.fish
set -l foreground DCD7BA normal
set -l selection 2D4F67 brcyan
set -l comment 727169 brblack
set -l red C34043 red
set -l orange FF9E64 brred
set -l yellow C0A36E yellow
set -l green 76946A green
set -l purple 957FB8 magenta
set -l cyan 7AA89F cyan
set -l pink D27E99 brmagenta

# Syntax Highlighting Colors
set -g fish_color_normal $foreground
set -g fish_color_command $cyan
set -g fish_color_keyword $pink
set -g fish_color_quote $yellow
set -g fish_color_redirection $foreground
set -g fish_color_end $orange
set -g fish_color_error $red
set -g fish_color_param $purple
set -g fish_color_comment $comment
set -g fish_color_selection --background=$selection
set -g fish_color_search_match --background=$selection
set -g fish_color_operator $green
set -g fish_color_escape $pink
set -g fish_color_autosuggestion $comment

# Completion Pager Colors
set -g fish_pager_color_progress $comment
set -g fish_pager_color_prefix $cyan
set -g fish_pager_color_completion $foreground
set -g fish_pager_color_description $comment

# --- Tide Prompt Customization (Kanagawa Style) ---

# Структура промпта
set -g tide_left_prompt_items pwd git newline character
set -g tide_right_prompt_items 
set -g tide_os_icon_display no

# Символы ввода
set -g tide_character_icon '~>'
set -g tide_character_vi_icon_default '~>'
set -g tide_character_vi_icon_replace '~>'
set -g tide_character_vi_icon_visual '~>'
set -g tide_character_vi_icon_insert '~>'

# Цвета промпта (используем переменные из этого же файла)
set -g tide_pwd_color_dirs $cyan          # Папки (7AA89F)
set -g tide_pwd_color_anchors $cyan       # Корневые папки
set -g tide_pwd_icon ""                   # Убираем иконку папки для минимализма
set -g tide_pwd_icon_unanchored ""

set -g tide_character_color $green        # Символ ~> (76946A)
set -g tide_character_color_failure $red  # Цвет ошибки (C34043)

set -g tide_git_color_branch $purple      # Ветки Git (957FB8)
set -g tide_git_color_dirty $orange       # Если есть изменения (FF9E64)

# Выключаем фоновые блоки (стиль Lean)
set -g tide_left_prompt_frame_enabled false
set -g tide_right_prompt_frame_enabled false

# Цвета Kanagawa для LS_COLORS (Hex коды из твоего файла)
# di (директории) = 7AA89F (cyan)
# ex (исполняемые) = C34043 (red)
# ln (ссылки) = 957FB8 (purple)
# or (битые ссылки) = FF9E64 (orange)
set -gx LS_COLORS "di=38;2;122;168;159:ex=38;2;195;64;67:ln=38;2;149;127;184:or=38;2;255;158;100:so=38;2;210;126;153:pi=38;2;192;163;110:bd=38;2;220;215;186:cd=38;2;220;215;186"


