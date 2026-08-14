#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
removed=0

log() {
  printf '\n==> %s\n' "$*"
}

remove_managed_link() {
  local target_path="$1" expected_source="$2"

  if [[ ! -L "$target_path" ]]; then
    [[ -e "$target_path" ]] && printf 'kept     %s (not a symlink)\n' "$target_path"
    return
  fi

  if [[ "$(readlink -f -- "$target_path")" != "$(readlink -f -- "$expected_source")" ]]; then
    printf 'kept     %s (points elsewhere)\n' "$target_path"
    return
  fi

  unlink -- "$target_path"
  printf 'removed  %s\n' "$target_path"
  removed=$((removed + 1))
}

log 'Removing self-shell configuration links'
for name in fish kitty tmux nvim fastfetch btop quickshell hypr waypaper; do
  remove_managed_link "$HOME/.config/$name" "$repo_dir/config/$name"
done

for name in .tmux.conf .gitconfig; do
  remove_managed_link "$HOME/$name" "$repo_dir/home/$name"
done

for script in "$repo_dir"/bin/*; do
  remove_managed_link "$HOME/.local/bin/$(basename -- "$script")" "$script"
done

remove_managed_link \
  "$HOME/.local/share/self-shell/wallpapers/wallpeper.jpg" \
  "$repo_dir/assets/wallpapers/wallpeper.jpg"
remove_managed_link \
  "$HOME/Documents/Wallpapers/wallpeper.jpg" \
  "$repo_dir/assets/wallpapers/wallpeper.jpg"

printf '\nDone. Removed %d managed link(s).\n' "$removed"
printf '%s\n' 'Removing ~/.config/hypr also removes the self-shell Quickshell autostart entries.'
printf '%s\n' 'System packages, login shell, Nautilus settings, MIME defaults, fonts,' \
  'tmux plugins, awww, mpvpaper, and the calendar environment were left unchanged.'
