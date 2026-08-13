#!/usr/bin/env bash
set -euo pipefail

exec env QSG_RENDER_LOOP=threaded quickshell --no-duplicate \
    --path "$HOME/.config/hypr/password"
