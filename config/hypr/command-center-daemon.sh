#!/usr/bin/env bash

set -euo pipefail

export QSG_RENDER_LOOP=threaded
exec quickshell --no-duplicate --path "${XDG_CONFIG_HOME:-${HOME}/.config}/hypr/command-center"
