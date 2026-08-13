#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
backup_dir="${XDG_STATE_HOME:-$HOME/.local/state}/self-shell/backups/$(date +%Y%m%d-%H%M%S)"
changed=0

link_path() {
  local source_path="$1" target_path="$2"
  mkdir -p "$(dirname -- "$target_path")"

  if [[ -L "$target_path" && "$(readlink -f -- "$target_path")" == "$(readlink -f -- "$source_path")" ]]; then
    printf 'ok      %s\n' "$target_path"
    return
  fi

  if [[ -e "$target_path" || -L "$target_path" ]]; then
    local relative_path="${target_path#"$HOME"/}"
    mkdir -p "$backup_dir/$(dirname -- "$relative_path")"
    mv -- "$target_path" "$backup_dir/$relative_path"
    printf 'backup  %s\n' "$target_path"
  fi

  ln -s -- "$source_path" "$target_path"
  printf 'linked  %s -> %s\n' "$target_path" "$source_path"
  changed=1
}

for name in fish kitty tmux nvim fastfetch btop; do
  link_path "$repo_dir/config/$name" "$HOME/.config/$name"
done

for name in .tmux.conf .gitconfig; do
  link_path "$repo_dir/home/$name" "$HOME/$name"
done

mkdir -p "$HOME/.local/bin"
for script in "$repo_dir"/bin/*; do
  link_path "$script" "$HOME/.local/bin/$(basename -- "$script")"
done

if [[ "${SELF_SHELL_OFFLINE:-0}" != 1 ]]; then
  if command -v fish >/dev/null 2>&1; then
    if ! fish -c 'type -q fisher'; then
      printf '\nInstall Fisher with:\n'
      printf '%s\n' '  fish -c "curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source; fisher update"'
    else
      fish -c 'fisher update'
    fi
  fi

  if command -v git >/dev/null 2>&1 && [[ ! -d "$HOME/.tmux/plugins/tpm" ]]; then
    git clone --depth 1 https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
  fi
else
  printf '\nOffline mode: skipped Fisher update and TPM installation.\n'
fi

if (( changed )) && [[ -d "$backup_dir" ]]; then
  printf '\nOld files were backed up to %s\n' "$backup_dir"
fi

printf '\nDone. Restart the terminal or run: exec fish\n'
