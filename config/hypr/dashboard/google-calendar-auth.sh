#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
    printf 'Использование: %s /путь/к/credentials.json\n' "$0" >&2
    exit 2
fi

exec "$HOME/.local/share/dashboard-calendar/venv/bin/python" \
    "$HOME/.config/hypr/dashboard/google_calendar.py" --auth "$1"
