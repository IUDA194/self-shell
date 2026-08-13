#!/usr/bin/env bash

set -euo pipefail

state_dir="${XDG_STATE_HOME:-${HOME}/.local/state}/hypr-clipboard"
items_dir="${state_dir}/items"
history_file="${state_dir}/history"
tmp_file="$(mktemp)"

mkdir -p "${items_dir}"
cat > "${tmp_file}"

if [[ ! -s "${tmp_file}" ]]; then
  rm -f "${tmp_file}"
  exit 0
fi

hash="$(sha256sum "${tmp_file}" | awk '{print $1}')"
item_file="${items_dir}/${hash}"

mv "${tmp_file}" "${item_file}"
touch "${history_file}"

{
  printf '%s\n' "${hash}"
  grep -Fvx "${hash}" "${history_file}" || true
} | awk 'NF && !seen[$0]++' | head -n 200 > "${history_file}.tmp"

mv "${history_file}.tmp" "${history_file}"
