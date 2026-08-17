#!/usr/bin/env bash

set -euo pipefail

action="${1:-status}"

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
      '{timezone:$timezone,ntp:($ntp=="yes"),synchronized:($synchronized=="yes")}'
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
  *) exit 2 ;;
esac
