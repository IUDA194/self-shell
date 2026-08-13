#!/usr/bin/env bash

set -euo pipefail

theme="${HOME}/.config/hypr/rofi-warm-obsidian.rasi"
state_dir="${XDG_STATE_HOME:-${HOME}/.local/state}/hypr-clipboard"
items_dir="${state_dir}/items"
history_file="${state_dir}/history"

mkdir -p "${items_dir}"
touch "${history_file}"

mapfile -t hashes < "${history_file}"

if [[ "${#hashes[@]}" -eq 0 ]]; then
  notify-send "Clipboard" "История буфера пуста"
  exit 0
fi

menu_input=""
for hash in "${hashes[@]}"; do
  item_file="${items_dir}/${hash}"
  [[ -f "${item_file}" ]] || continue

  preview="$(tr '\n' ' ' < "${item_file}" | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//' | cut -c1-140)"
  [[ -n "${preview}" ]] || preview="[empty]"
  menu_input+="${preview}"$'\t'"${hash}"$'\n'
done

selection="$(
  printf '%s' "${menu_input}" |
    rofi -dmenu \
      -i \
      -p "Clipboard" \
      -theme "${theme}" \
      -display-columns 1 \
      -display-column-separator $'\t'
)"

[[ -n "${selection}" ]] || exit 0

hash="${selection##*$'\t'}"
item_file="${items_dir}/${hash}"
[[ -f "${item_file}" ]] || exit 1

wl-copy < "${item_file}"
notify-send "Clipboard" "Элемент из истории скопирован"
