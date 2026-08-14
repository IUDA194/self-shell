#!/usr/bin/env bash

set -euo pipefail

export SELF_SHELL_SCREENSHOT_FREEZE="${XDG_RUNTIME_DIR:-/tmp}/self-shell-screenshot-freeze-${UID}.png"
export QSG_RENDER_LOOP=threaded

exec quickshell --no-duplicate --path "${XDG_CONFIG_HOME:-${HOME}/.config}/hypr/screenshot"
