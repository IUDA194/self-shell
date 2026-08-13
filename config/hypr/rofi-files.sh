#!/usr/bin/env bash

set -euo pipefail

theme="${HOME}/.config/hypr/rofi-warm-obsidian.rasi"
selection="$(
  plocate -i -0 --existing --regex "^${HOME}/.*" 2>/dev/null |
    tr '\0' '\n' |
    rg -v '/(\.git|node_modules|\.cache|__pycache__|target)(/|$)' |
    rofi -dmenu \
      -i \
      -matching fuzzy \
      -sorting-method fzf \
      -sort \
      -p "Files" \
      -theme "${theme}"
)"

[[ -n "${selection}" ]] || exit 0

exec xdg-open "${selection}"
