#!/usr/bin/env bash

set -euo pipefail

state_dir="${XDG_STATE_HOME:-${HOME}/.local/state}/hypr-clipboard"
items_dir="${state_dir}/items"
history_file="${state_dir}/history"

mkdir -p "${items_dir}"
touch "${history_file}"

case "${1:-}" in
  --list)
    while IFS= read -r hash; do
      [[ "${hash}" =~ ^[0-9a-f]{64}$ ]] || continue
      item_file="${items_dir}/${hash}"
      [[ -f "${item_file}" ]] || continue

      preview="$(tr '\n\t' '  ' < "${item_file}" | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//' | cut -c1-220)"
      [[ -n "${preview}" ]] || preview="[пустой элемент]"
      printf '%s\t%s\n' "${hash}" "${preview}"
    done < "${history_file}"
    ;;

  --copy)
    hash="${2:-}"
    [[ "${hash}" =~ ^[0-9a-f]{64}$ ]] || exit 2
    item_file="${items_dir}/${hash}"
    [[ -f "${item_file}" ]] || exit 1
    wl-copy < "${item_file}"
    notify-send "Clipboard" "Элемент из истории скопирован"
    ;;

  *)
    printf 'Использование: %s --list | --copy HASH\n' "$0" >&2
    exit 2
    ;;
esac
