#!/usr/bin/env bash
set -euo pipefail

address="${1:-}"
address="${address#0x}"
[[ "$address" =~ ^[0-9a-fA-F]+$ ]] || exit 2

cursor="$(hyprctl cursorpos -j)"
cursor_x="$(jq -r '.x' <<<"$cursor")"
cursor_y="$(jq -r '.y' <<<"$cursor")"

hyprctl dispatch focuswindow "address:0x${address}" >/dev/null

# Hyprland performs its focus warp after the dispatch has returned.
sleep 0.12
hyprctl dispatch movecursor "$cursor_x" "$cursor_y" >/dev/null
