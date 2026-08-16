#!/usr/bin/env bash

set -euo pipefail

case "${1:-next}" in
  en) layout=0 ;;
  ru) layout=1 ;;
  next) layout=next ;;
  *)
    printf 'Usage: %s [en|ru|next]\n' "${0##*/}" >&2
    exit 2
    ;;
esac

hyprctl switchxkblayout all "$layout" >/dev/null
pkill -RTMIN+11 waybar || true
