#!/usr/bin/env bash

set -euo pipefail

action="${1:-status}"
session_state="${XDG_STATE_HOME:-$HOME/.local/state}/self-shell/session.json"

selected_session() {
  jq -r '.session // "hyprland"' "$session_state" 2>/dev/null || printf 'hyprland\n'
}

case "$action" in
  list-timezones)
    timedatectl list-timezones 2>/dev/null || find /usr/share/zoneinfo -type f \
      ! -path '*/posix/*' ! -path '*/right/*' -printf '%P\n' | sort
    ;;
  status)
    timezone="$(timedatectl show --value -p Timezone 2>/dev/null || cat /etc/timezone 2>/dev/null || printf UTC)"
    ntp="$(timedatectl show --value -p NTP 2>/dev/null || printf no)"
    synchronized="$(timedatectl show --value -p NTPSynchronized 2>/dev/null || printf no)"
    jq -cn --arg timezone "$timezone" --arg ntp "$ntp" --arg synchronized "$synchronized" \
      --arg session "$(selected_session)" \
      '{timezone:$timezone,ntp:($ntp=="yes"),synchronized:($synchronized=="yes"),session:$session}'
    ;;
  set-time)
    value="${2:-}"
    [[ "$value" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]][0-9]{2}:[0-9]{2}(:[0-9]{2})?$ ]] || exit 2
    exec pkexec "$0" privileged-set-time "$value"
    ;;
  set-timezone)
    value="${2:-}"
    [[ "$value" =~ ^[A-Za-z0-9_+.-]+(/[A-Za-z0-9_+.-]+)+$ ]] || exit 2
    [[ -e "/usr/share/zoneinfo/$value" ]] || exit 2
    exec pkexec "$0" privileged-set-timezone "$value"
    ;;
  set-ntp)
    value="${2:-}"
    [[ "$value" == true || "$value" == false ]] || exit 2
    exec pkexec "$0" privileged-set-ntp "$value"
    ;;
  hard-reload)
    log_file="${XDG_CACHE_HOME:-$HOME/.cache}/self-shell-hard-reload.log"
    mkdir -p "$(dirname "$log_file")"
    nohup setsid "$HOME/.config/hypr/self-shell-hard-reload.sh" \
      </dev/null >"$log_file" 2>&1 &
    ;;
  set-session)
    value="${2:-}"
    [[ "$value" == hyprland || "$value" == niri ]] || exit 2
    mkdir -p "$(dirname -- "$session_state")"
    temporary="$(mktemp "${session_state}.XXXXXX")"
    jq -cn --arg session "$value" '{session:$session}' > "$temporary"
    mv -- "$temporary" "$session_state"
    ;;
  switch-session)
    value="${2:-}"
    [[ "$value" == hyprland || "$value" == niri ]] || exit 2
    desktop_file="/usr/share/wayland-sessions/${value}.desktop"
    [[ -r "$desktop_file" ]] || {
      notify-send "Сеанс рабочего стола" "Сессия ${value} не установлена"
      exit 1
    }
    "$0" set-session "$value"
    pkexec "$0" privileged-select-sddm-session "$(basename -- "$desktop_file")"
    if command -v hyprctl >/dev/null 2>&1 && hyprctl monitors >/dev/null 2>&1; then
      hyprctl dispatch exit
    elif command -v niri >/dev/null 2>&1; then
      niri msg action quit
    fi
    ;;
  privileged-set-time)
    [[ "$(id -u)" -eq 0 ]] || exit 1
    timedatectl set-ntp false
    timedatectl set-time "$2"
    ;;
  privileged-set-timezone)
    [[ "$(id -u)" -eq 0 ]] || exit 1
    timedatectl set-timezone "$2"
    ;;
  privileged-set-ntp)
    [[ "$(id -u)" -eq 0 ]] || exit 1
    timedatectl set-ntp "$2"
    ;;
  privileged-select-sddm-session)
    [[ "$(id -u)" -eq 0 ]] || exit 1
    value="${2:-}"
    [[ "$value" == hyprland.desktop || "$value" == niri.desktop ]] || exit 2
    state_file=/var/lib/sddm/state.conf
    [[ -e "$state_file" ]] || state_file=/var/lib/sddm/.config/sddm/state.conf
    mkdir -p "$(dirname -- "$state_file")"
    [[ -e "$state_file" ]] || : > "$state_file"
    temporary="$(mktemp "${state_file}.XXXXXX")"
    awk -v session="$value" '
      BEGIN { in_last=0; saw_last=0; wrote_session=0 }
      /^\[Last\]$/ {
        in_last=1; saw_last=1; print; next
      }
      /^\[/ {
        if (in_last && !wrote_session) { print "Session=" session; wrote_session=1 }
        in_last=0; print; next
      }
      in_last && /^Session=/ {
        if (!wrote_session) { print "Session=" session; wrote_session=1 }
        next
      }
      { print }
      END {
        if (!saw_last) print "[Last]"
        if (!wrote_session) print "Session=" session
      }
    ' "$state_file" 2>/dev/null > "$temporary"
    mv -- "$temporary" "$state_file"
    ;;
  *) exit 2 ;;
esac
