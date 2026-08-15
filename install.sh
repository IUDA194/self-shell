#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
backup_dir="${XDG_STATE_HOME:-$HOME/.local/state}/self-shell/backups/$(date +%Y%m%d-%H%M%S)"
changed=0

log() {
  printf '\n==> %s\n' "$*"
}

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

install_fedora_packages() {
  local packages=(
    bash btop brightnessctl cargo curl dnf5-plugins fastfetch fd-find fish fontconfig gcc git
    grim hyprland hyprlock hyprsunset ImageMagick jq kde-connect kitty libnotify lz4-devel meson mpv-devel nautilus
    NetworkManager neovim ninja-build pass plocate playerctl pkgconf-pkg-config
    python3 python3-pip qt6-qtimageformats qt6-qtmultimedia qt6-qtsvg qt6-qtvirtualkeyboard
    ripgrep rofi scdoc sddm slurp sqlite tesseract tesseract-langpack-eng
    tesseract-langpack-rus tmux wayland-devel
    wayland-protocols-devel wf-recorder wireplumber wl-clipboard wtype xdg-utils
    xz zoxide
  )

  # Do not replace a full RPM Fusion FFmpeg installation with Fedora's free build.
  command -v ffmpeg >/dev/null 2>&1 || packages+=(ffmpeg-free)

  sudo dnf install -y --skip-unavailable "${packages[@]}"

  install_quickshell_fedora
}

install_quickshell_fedora() {
  command -v quickshell >/dev/null 2>&1 && return

  local fedora_version
  fedora_version="$(rpm -E '%{fedora}')"
  [[ "$fedora_version" =~ ^[0-9]+$ ]] || {
    printf 'Could not determine the Fedora version: %s\n' "$fedora_version" >&2
    exit 1
  }

  if (( fedora_version == 43 )); then
    log 'Enabling the official Quickshell COPR for Fedora 43'
    sudo dnf -y copr enable errornointernet/quickshell
  elif (( fedora_version < 43 )); then
    printf 'Fedora %s is unsupported; Fedora 43 or newer is required.\n' "$fedora_version" >&2
    exit 1
  fi

  sudo dnf install -y quickshell
  command -v quickshell >/dev/null 2>&1 || {
    printf 'Quickshell installation completed, but its executable was not found.\n' >&2
    exit 1
  }
}

install_arch_packages() {
  local packages=(
    awww bash btop brightnessctl curl fastfetch fd fish fontconfig gcc git
    grim hyprland hyprlock hyprsunset imagemagick jq kdeconnect kitty libnotify meson mpv nautilus networkmanager
    neovim ninja pass plocate playerctl python ripgrep rofi sddm slurp sqlite tesseract
    tesseract-data-eng tesseract-data-rus tmux
    qt6-imageformats qt6-multimedia qt6-svg qt6-virtualkeyboard
    wf-recorder wireplumber wl-clipboard wtype xdg-utils xz zoxide quickshell
  )
  sudo pacman -S --needed --noconfirm "${packages[@]}"
}

install_packages() {
  if command -v dnf >/dev/null 2>&1; then
    install_fedora_packages
  elif command -v pacman >/dev/null 2>&1; then
    install_arch_packages
  else
    printf 'Unsupported package manager. Install dependencies from README.md, then run:\n' >&2
    printf '  SELF_SHELL_SKIP_PACKAGES=1 ./install.sh\n' >&2
    exit 1
  fi
}

install_awww() {
  command -v awww >/dev/null 2>&1 && command -v awww-daemon >/dev/null 2>&1 && return

  command -v cargo >/dev/null 2>&1 || {
    printf 'cargo is required to install awww\n' >&2
    exit 1
  }

  local source_dir
  source_dir="$(mktemp -d)"
  trap 'rm -rf -- "$source_dir"' RETURN

  git clone --depth 1 --branch v0.12.1 https://codeberg.org/LGFae/awww.git "$source_dir/awww"
  cargo install --locked --path "$source_dir/awww/client"
  cargo install --locked --path "$source_dir/awww/daemon"

  trap - RETURN
  rm -rf -- "$source_dir"
}

install_mpvpaper() {
  command -v mpvpaper >/dev/null 2>&1 && return

  local source_dir
  source_dir="$(mktemp -d)"
  trap 'rm -rf -- "$source_dir"' RETURN

  git clone https://github.com/GhostNaN/mpvpaper.git "$source_dir/mpvpaper"
  git -C "$source_dir/mpvpaper" checkout 8f375262cf542fd6c696f97837e2f28ac9440262
  meson setup "$source_dir/mpvpaper/build" "$source_dir/mpvpaper" --prefix="$HOME/.local"
  ninja -C "$source_dir/mpvpaper/build" install

  trap - RETURN
  rm -rf -- "$source_dir"
}

install_nerd_font() {
  if fc-match 'JetBrainsMono Nerd Font Mono' 2>/dev/null | grep -Fqi 'JetBrainsMono Nerd Font'; then
    return
  fi

  local font_dir archive_dir
  font_dir="$HOME/.local/share/fonts/JetBrainsMonoNerdFont"
  archive_dir="$(mktemp -d)"
  trap 'rm -rf -- "$archive_dir"' RETURN

  mkdir -p "$font_dir"
  curl --fail --location --retry 3 \
    https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz \
    --output "$archive_dir/JetBrainsMono.tar.xz"
  tar -xJf "$archive_dir/JetBrainsMono.tar.xz" -C "$font_dir"
  fc-cache -f "$font_dir"

  trap - RETURN
  rm -rf -- "$archive_dir"
}

install_calendar_environment() {
  local venv="$HOME/.local/share/dashboard-calendar/venv"
  python3 -m venv "$venv"
  "$venv/bin/python" -m pip install --upgrade pip
  "$venv/bin/python" -m pip install \
    google-api-python-client google-auth-httplib2 google-auth-oauthlib
}

install_nautilus_config() {
  if ! command -v dconf >/dev/null 2>&1; then
    printf 'warning dconf is unavailable; skipped Nautilus settings\n' >&2
    return
  fi

  if ! dconf load /org/gnome/nautilus/ < "$repo_dir/config/nautilus/settings.ini"; then
    printf 'warning could not apply Nautilus settings in this session\n' >&2
  fi
}

set_default_file_manager() {
  if ! command -v xdg-mime >/dev/null 2>&1; then
    printf 'warning xdg-mime is unavailable; Nautilus was not set as the default file manager\n' >&2
    return
  fi

  local desktop_file='org.gnome.Nautilus.desktop'
  local mime_type
  for mime_type in inode/directory application/x-gnome-saved-search; do
    if ! xdg-mime default "$desktop_file" "$mime_type"; then
      printf 'warning could not set Nautilus as the default handler for %s\n' "$mime_type" >&2
    fi
  done
}

if [[ "${SELF_SHELL_SKIP_PACKAGES:-0}" != 1 ]]; then
  log 'Installing system packages'
  install_packages

  log 'Installing awww'
  install_awww

  log 'Installing mpvpaper for video wallpapers'
  install_mpvpaper

  log 'Installing JetBrainsMono Nerd Font'
  install_nerd_font
fi

log 'Linking the complete configuration'
for name in fish kitty tmux nvim fastfetch btop quickshell hypr waypaper; do
  link_path "$repo_dir/config/$name" "$HOME/.config/$name"
done

for name in .tmux.conf .gitconfig; do
  link_path "$repo_dir/home/$name" "$HOME/$name"
done

log 'Applying Nautilus settings'
install_nautilus_config

log 'Setting Nautilus as the default file manager'
set_default_file_manager

mkdir -p "$HOME/.local/bin" "$HOME/.local/share/self-shell/wallpapers" "$HOME/Documents/Wallpapers"
for script in "$repo_dir"/bin/*; do
  link_path "$script" "$HOME/.local/bin/$(basename -- "$script")"
done
link_path "$repo_dir/assets/wallpapers/wallpeper.jpg" \
  "$HOME/.local/share/self-shell/wallpapers/wallpeper.jpg"

if [[ ! -e "$HOME/Documents/Wallpapers/wallpeper.jpg" ]]; then
  link_path "$repo_dir/assets/wallpapers/wallpeper.jpg" \
    "$HOME/Documents/Wallpapers/wallpeper.jpg"
fi

if [[ "${SELF_SHELL_SKIP_SDDM:-0}" != 1 && "${SELF_SHELL_OFFLINE:-0}" != 1 ]]; then
  log 'Installing and syncing SilentSDDM'
  "$repo_dir/bin/self-shell-sddm-sync"
fi

if [[ "${SELF_SHELL_OFFLINE:-0}" != 1 ]]; then
  # Fisher and Tide are bundled in config/fish. Running `fisher update` here
  # would try to overwrite those tracked files through the config symlink.
  log 'Installing tmux plugins'
  if [[ ! -d "$HOME/.tmux/plugins/tpm" ]]; then
    git clone --depth 1 https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
  fi
  "$HOME/.tmux/plugins/tpm/bin/install_plugins"

  log 'Preparing the dashboard calendar environment'
  install_calendar_environment
else
  printf '\nOffline mode: skipped plugins and dashboard Python packages.\n'
fi

fish_path="$(command -v fish)"
current_shell="$(getent passwd "$(id -un)" | cut -d: -f7)"
if [[ "$current_shell" != "$fish_path" && "${SELF_SHELL_SKIP_CHSH:-0}" != 1 ]]; then
  log "Setting the login shell to $fish_path"
  if [[ "$(id -u)" -eq 0 ]]; then
    usermod --shell "$fish_path" "$(id -un)"
  else
    sudo usermod --shell "$fish_path" "$(id -un)"
  fi
fi

if (( changed )) && [[ -d "$backup_dir" ]]; then
  printf '\nOld files were backed up to %s\n' "$backup_dir"
fi

printf '\nDone. Open Kitty (or run: exec fish); Fish will attach to tmux session main.\n'
