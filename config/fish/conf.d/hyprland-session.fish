# A long-lived tmux server can retain the environment of an old Hyprland
# instance. Refresh the signature from the newest live control socket so
# hyprctl and Quickshell launched from new panes reach the current compositor.
if set -q NIRI_SOCKET
    set -e HYPRLAND_INSTANCE_SIGNATURE
    if set -q TMUX
        command tmux set-environment -gu HYPRLAND_INSTANCE_SIGNATURE 2>/dev/null
    end
else if set -q XDG_RUNTIME_DIR; and test -d "$XDG_RUNTIME_DIR/hypr"
    set -l active_hypr_socket (command find "$XDG_RUNTIME_DIR/hypr" \
        -mindepth 2 -maxdepth 2 -type s -name .socket.sock \
        -printf '%T@ %h\n' 2>/dev/null | command sort -nr | command head -n 1)

    if test -n "$active_hypr_socket"
        set -l active_hypr_dir (string replace -r '^[^ ]+ ' '' -- "$active_hypr_socket")
        set -gx HYPRLAND_INSTANCE_SIGNATURE (path basename "$active_hypr_dir")

        if set -q TMUX
            command tmux set-environment -g HYPRLAND_INSTANCE_SIGNATURE \
                "$HYPRLAND_INSTANCE_SIGNATURE" 2>/dev/null
        end
    end
end

# Qt requires a locale that is actually installed.  Fedora/Arch minimal
# installations commonly provide only C.utf8, while a stale en_US.UTF-8
# setting makes Kitty fail locale initialization.
if not set -q LANG; or not command locale -a 2>/dev/null | string match -q -i -e -- "$LANG"
    set -gx LANG C.utf8
end
