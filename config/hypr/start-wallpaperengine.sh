#!/usr/bin/env bash

set -u

LOG_FILE="/tmp/linux-wallpaperengine-hypr-start.log"
ENGINE_DIR="$HOME/Documents/Wallpapers/linux-wallpaperengine/build/output"
ASSETS_DIR="$HOME/Games/steamapps/common/wallpaper_engine/assets"
WALLPAPER_DIR="$HOME/Games/steamapps/workshop/content/431960/3237672440"

MONITORS=("DP-1" "HDMI-A-1")

log() {
    printf '[%s] %s\n' "$(date '+%F %T')" "$*" >> "$LOG_FILE"
}

log "startup requested"

# Ждём, пока Hyprland увидит все мониторы
for MONITOR_NAME in "${MONITORS[@]}"; do
    for _ in $(seq 1 15); do
        if hyprctl monitors 2>/dev/null | grep -q "Monitor ${MONITOR_NAME} "; then
            log "monitor ${MONITOR_NAME} detected"
            break
        fi
        sleep 1
    done

    if ! hyprctl monitors 2>/dev/null | grep -q "Monitor ${MONITOR_NAME} "; then
        log "monitor ${MONITOR_NAME} was not detected in time"
    fi
done

cd "$ENGINE_DIR" || {
    log "cannot cd to ${ENGINE_DIR}"
    exit 1
}

export __GLX_VENDOR_LIBRARY_NAME=nvidia
export __NV_PRIME_RENDER_OFFLOAD=1

# Убиваем старые экземпляры этих обоев
pkill -f "linux-wallpaperengine.*${WALLPAPER_DIR}" 2>/dev/null || true

sleep 1

# Запускаем отдельный экземпляр на каждый монитор
for MONITOR_NAME in "${MONITORS[@]}"; do
    if hyprctl monitors 2>/dev/null | grep -q "Monitor ${MONITOR_NAME} "; then
        log "launching wallpaper on ${MONITOR_NAME}"

        ./linux-wallpaperengine \
            --assets-dir "$ASSETS_DIR" \
            --screen-root "$MONITOR_NAME" \
            --bg "$WALLPAPER_DIR" \
            --fps 60 >> "$LOG_FILE" 2>&1 &
    else
        log "skipping ${MONITOR_NAME}, monitor not found"
    fi
done

sleep 3

if pgrep -af "linux-wallpaperengine.*${WALLPAPER_DIR}" >/dev/null 2>&1; then
    log "launch succeeded"
    exit 0
fi

log "launch failed"
exit 1
