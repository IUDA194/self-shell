if status is-interactive

    alias vim="nvim"
    alias vi="nvim"
    alias md="mkdir -p"
    alias p="pwd"
    alias gp="git push"
    alias z="zoxide"
    if type -q rip
        alias rm="rip"
    end

    if type -q zoxide
        zoxide init fish | source
    end

    set -g __self_shell_text_theme_file ~/.cache/self-shell/fish-text-theme.fish
    if test -r $__self_shell_text_theme_file
        source $__self_shell_text_theme_file
        set -g __self_shell_text_theme_mtime (stat -c %y $__self_shell_text_theme_file 2>/dev/null)
    else
        source ~/.config/fish/obsidian-warm.fish
        set -g __self_shell_text_theme_mtime 0
    end

    function __self_shell_reload_text_theme
        test -r $__self_shell_text_theme_file; or return
        set -l current_mtime (stat -c %y $__self_shell_text_theme_file 2>/dev/null)
        if test "$current_mtime" != "$__self_shell_text_theme_mtime"
            source $__self_shell_text_theme_file
            set -g __self_shell_text_theme_mtime $current_mtime
        end
    end

    function __self_shell_reload_text_theme_before --on-event fish_preexec
        __self_shell_reload_text_theme
    end

    function __self_shell_reload_text_theme_after --on-event fish_postexec
        __self_shell_reload_text_theme
    end

    if test -d /opt/homebrew/bin
        fish_add_path /opt/homebrew/bin
    end

    set -g tide_left_prompt_items pwd git newline character
    set -g tide_right_prompt_items
    set -g tide_os_icon_display no
    set -g tide_character_icon '~>'
    set -g tide_character_vi_icon_default '~>'
    set -g tide_character_vi_icon_insert '~>'

    function fish_greeting
        echo 'Hi'
    end

    if type -q tmux; and not set -q TMUX
        exec tmux new-session -A -s main
    end
end

fish_add_path "$HOME/.local/bin" "$HOME/.npm-global/bin"

# opencode
fish_add_path "$HOME/.opencode/bin"

# Added by LM Studio CLI (lms)
fish_add_path "$HOME/.lmstudio/bin"
# End of LM Studio CLI section

# bun
set --export BUN_INSTALL "$HOME/.bun"
set --export PATH $BUN_INSTALL/bin $PATH

fish_add_path "$HOME/.spicetify"

# kimi-code
fish_add_path -g "$HOME/.kimi-code/bin"

# pass
set -gx PASSWORD_STORE_DIR "$HOME/.pass/passwords"


# Added by Antigravity CLI installer
set -gx PATH "/home/yaroslav/.local/bin" $PATH
