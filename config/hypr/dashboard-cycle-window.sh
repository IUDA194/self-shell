#!/usr/bin/env bash

# Quickshell owns both the visual switcher and the window order.
quickshell ipc --path "$HOME/.config/hypr/dashboard" \
    call dock cycle >/dev/null 2>&1
