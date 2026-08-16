#!/usr/bin/env bash
set -u

command_name="${1:-read}"
state_dir="${XDG_RUNTIME_DIR:-/tmp}/self-shell-command-center"
gamma_state="$state_dir/brightness"

ensure_hyprsunset() {
  command -v hyprsunset >/dev/null 2>&1 || return 1
  command -v hyprctl >/dev/null 2>&1 || return 1
  if ! pgrep -x hyprsunset >/dev/null; then
    hyprsunset --identity </dev/null >/dev/null 2>&1 &
    for _ in {1..20}; do
      pgrep -x hyprsunset >/dev/null && return 0
      sleep 0.05
    done
    return 1
  fi
}

if [[ "$command_name" == "read" ]]; then
  value="$(brightnessctl -c backlight -m 2>/dev/null | awk -F, 'NR == 1 {gsub(/%/, "", $4); print $4}')"
  if [[ "$value" =~ ^[0-9]+$ ]]; then
    printf 'backlight\t-\t%s\n' "$value"
    exit 0
  fi

  if command -v hyprsunset >/dev/null 2>&1 && command -v hyprctl >/dev/null 2>&1; then
    if [[ -r "$gamma_state" ]]; then
      value="$(<"$gamma_state")"
    else
      value=100
    fi
    [[ "$value" =~ ^[0-9]+$ ]] || value=100
    printf 'gamma\t-\t%s\n' "$value"
    exit 0
  fi

  exit 1
fi

if [[ "$command_name" == "ensure" ]]; then
  ensure_hyprsunset
  exit $?
fi

if [[ "$command_name" == "change" ]]; then
  delta="${2:-}"
  [[ "$delta" =~ ^-?[0-9]+$ ]] || exit 2
  IFS=$'\t' read -r backend device value < <("${BASH_SOURCE[0]}" read)
  value=$((value + delta))
  ((value < 1)) && value=1
  ((value > 100)) && value=100
  exec "${BASH_SOURCE[0]}" set "$backend" "$device" "$value"
fi

if [[ "$command_name" == "set" ]]; then
  backend="${2:-}"
  device="${3:-}"
  value="${4:-}"
  [[ "$value" =~ ^[0-9]+$ ]] || exit 2

  case "$backend" in
    backlight) brightnessctl -c backlight set "$value%" ;;
    gamma)
      ensure_hyprsunset || exit 1
      hyprctl hyprsunset gamma "$value" >/dev/null || exit 1
      mkdir -p "$state_dir"
      printf '%s\n' "$value" >"$gamma_state"
      ;;
    *) exit 2 ;;
  esac
  exit $?
fi

exit 2
