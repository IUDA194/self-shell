#!/usr/bin/env bash

set -euo pipefail

state_dir="${XDG_STATE_HOME:-${HOME}/.local/state}/hypr-clipboard"
theme="${HOME}/.config/hypr/rofi-warm-obsidian.rasi"

choice="$(
  printf 'Нет\nДа\n' |
    rofi -dmenu \
      -i \
      -p "Очистить clipboard history?" \
      -theme "${theme}" \
      -theme-str 'window {width: 360px;}' \
      -theme-str 'listview {lines: 2;}'
)"

if [[ "${choice}" != "Да" ]]; then
  exit 0
fi

rm -rf "${state_dir}"
mkdir -p "${state_dir}/items"
: > "${state_dir}/history"

notify-send "Clipboard" "История буфера очищена"
