#!/usr/bin/env bash

set -euo pipefail

device_line="$(kdeconnect-cli --list-devices --id-name-only 2>/dev/null | head -n1 || true)"
if [[ -z "$device_line" ]]; then
  printf '\tТелефон не сопряжён\t0\t-1\t0\n'
  exit 0
fi

device_id="${device_line%% *}"
device_name="${device_line#* }"
online=0
if kdeconnect-cli --list-available --id-only 2>/dev/null | grep -qx "$device_id"; then
  online=1
fi

charge=-1
charging=0
if [[ "$online" == 1 ]]; then
  device_path="/modules/kdeconnect/devices/$device_id/battery"
  charge="$(gdbus call --session --dest org.kde.kdeconnect --object-path "$device_path" \
    --method org.freedesktop.DBus.Properties.Get org.kde.kdeconnect.device.battery charge \
    2>/dev/null | sed -n 's/.*<\([-0-9]*\)>.*/\1/p')"
  charging_text="$(gdbus call --session --dest org.kde.kdeconnect --object-path "$device_path" \
    --method org.freedesktop.DBus.Properties.Get org.kde.kdeconnect.device.battery isCharging \
    2>/dev/null || true)"
  [[ "$charging_text" == *true* ]] && charging=1
  charge="${charge:--1}"
fi

printf '%s\t%s\t%s\t%s\t%s\n' "$device_id" "$device_name" "$online" "$charge" "$charging"
