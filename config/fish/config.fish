if status is-interactive

    alias vim="nvim"
    alias vi="nvim"
    alias md="mkdir -p"
    alias p="pwd"
    alias gp="git push"
    alias z="zoxide"
    alias rm="rip"

    if type -q zoxide
        zoxide init fish | source
    end

    source ~/.config/fish/obsidian-warm.fish

    if test -d /opt/homebrew/bin
        fish_add_path /opt/homebrew/bin
    end

    set -g tide_left_prompt_items pwd git newline character
    set -g tide_right_prompt_items
    set -g tide_os_icon_display no
    set -g tide_character_icon '~>'
    set -g tide_character_vi_icon_default '~>'
    set -g tide_character_vi_icon_insert '~>'

    set -gx DOCKER_HOST unix:///run/user/(id -u)/docker.sock

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
