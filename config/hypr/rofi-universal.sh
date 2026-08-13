#!/usr/bin/env bash

set -euo pipefail

theme="${HOME}/.config/hypr/rofi-warm-obsidian.rasi"

exec rofi \
  -show combi \
  -modes "combi,drun,run" \
  -combi-modi "drun,run" \
  -matching fuzzy \
  -sorting-method fzf \
  -sort \
  -show-icons \
  -display-combi "Apps/Cmd" \
  -display-drun "Apps" \
  -display-run "Cmd" \
  -theme "${theme}"
