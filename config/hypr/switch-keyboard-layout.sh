#!/usr/bin/env bash

set -euo pipefail

hyprctl switchxkblayout all next >/dev/null
pkill -RTMIN+11 waybar || true
