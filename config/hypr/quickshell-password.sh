#!/usr/bin/env bash
set -euo pipefail

export PASSWORD_STORE_DIR="$HOME/.pass/passwords"

exec env QSG_RENDER_LOOP=threaded quickshell --no-duplicate \
    --path "$HOME/.config/hypr/password"
