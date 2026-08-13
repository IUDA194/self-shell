#!/usr/bin/env bash

set -euo pipefail

config_home="${XDG_CONFIG_HOME:-${HOME}/.config}"
theme="${config_home}/quickshell/themes/rofi-power-menu.rasi"
rofi_args=(
  -dmenu
  -i
  -theme "$theme"
  -theme-str 'window { width: 380px; }'
  -theme-str 'listview { lines: 8; }'
)

wifi_state="$(nmcli radio wifi 2>/dev/null || printf 'disabled')"

if [[ "$wifi_state" != "enabled" ]]; then
  enable_label="󰖩  Включить Wi-Fi"
  choice="$(printf '%s\n' "$enable_label" | rofi "${rofi_args[@]}" -p "Wi-Fi")" || exit 0
  if [[ "$choice" == "$enable_label" ]]; then
    nmcli radio wifi on
    pkill -SIGRTMIN+9 waybar 2>/dev/null || true
  fi
  exit 0
fi

active_ssid="$(nmcli -t --escape no -f ACTIVE,SSID device wifi list 2>/dev/null | sed -n 's/^yes://p' | head -n1)"
off_label="󰖪  Выключить Wi-Fi"
refresh_label="󰑐  Обновить список"

declare -a labels=("$refresh_label" "$off_label")
declare -A ssid_by_label=()

while IFS= read -r ssid; do
  [[ -n "$ssid" ]] || continue
  if [[ "$ssid" == "$active_ssid" ]]; then
    label="●  ${ssid}"
  else
    label="○  ${ssid}"
  fi
  labels+=("$label")
  ssid_by_label["$label"]="$ssid"
done < <(nmcli -t --escape no -f SSID device wifi list --rescan yes 2>/dev/null | awk 'NF && !seen[$0]++')

choice="$(printf '%s\n' "${labels[@]}" | rofi "${rofi_args[@]}" -p "Wi-Fi")" || exit 0

case "$choice" in
  "$off_label")
    nmcli radio wifi off
    ;;
  "$refresh_label")
    exec "$0"
    ;;
  "")
    exit 0
    ;;
  *)
    ssid="${ssid_by_label[$choice]:-}"
    [[ -n "$ssid" ]] || exit 0
    [[ "$ssid" != "$active_ssid" ]] || exit 0

    if ! error="$(nmcli --wait 12 device wifi connect "$ssid" 2>&1)"; then
      password="$(printf '' | rofi "${rofi_args[@]}" -password -p "Пароль · ${ssid}")" || exit 0
      [[ -n "$password" ]] || exit 0
      if ! error="$(nmcli --wait 20 device wifi connect "$ssid" password "$password" 2>&1)"; then
        notify-send "Wi-Fi" "Не удалось подключиться к ${ssid}\n${error}" 2>/dev/null || true
        exit 1
      fi
    fi
    ;;
esac

pkill -SIGRTMIN+9 waybar 2>/dev/null || true
