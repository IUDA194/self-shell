#!/usr/bin/env bash

set -u

exec "$HOME/.local/share/dashboard-calendar/venv/bin/python" \
    "$HOME/.config/hypr/dashboard/google_calendar.py"
