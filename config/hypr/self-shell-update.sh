#!/usr/bin/env bash

set -euo pipefail

script_path="$(readlink -f -- "${BASH_SOURCE[0]}")"
repo_dir="$(cd -- "$(dirname -- "$script_path")/../.." && pwd)"
config_file="${XDG_CONFIG_HOME:-$HOME/.config}/self-shell/update.json"
state_file="${XDG_STATE_HOME:-$HOME/.local/state}/self-shell/update.json"
lock_file="${XDG_RUNTIME_DIR:-/tmp}/self-shell-update.lock"

read_mode() { jq -r '.mode // "off"' "$config_file" 2>/dev/null || printf 'off\n'; }
read_days() { jq -r '.days // 7' "$config_file" 2>/dev/null || printf '7\n'; }

write_config() {
  local mode="$1" days="$2" temporary
  mkdir -p "$(dirname -- "$config_file")"
  temporary="$(mktemp "${config_file}.XXXXXX")"
  jq -cn --arg mode "$mode" --argjson days "$days" '{mode:$mode,days:$days}' > "$temporary"
  mv -- "$temporary" "$config_file"
}

write_state() {
  local status="$1" message="$2" available="${3:-0}" temporary
  mkdir -p "$(dirname -- "$state_file")"
  temporary="$(mktemp "${state_file}.XXXXXX")"
  jq -cn --argjson checkedAt "$(date +%s)" --arg status "$status" \
    --arg message "$message" --argjson available "$available" \
    '{checkedAt:$checkedAt,status:$status,message:$message,available:$available}' > "$temporary"
  mv -- "$temporary" "$state_file"
}

status_json() {
  local mode days state
  mode="$(read_mode)"
  days="$(read_days)"
  state='{}'
  [[ -s "$state_file" ]] && state="$(cat "$state_file")"
  jq -cn --arg mode "$mode" --argjson days "$days" --argjson state "$state" \
    '{mode:$mode,days:$days} + $state'
}

notify() {
  command -v notify-send >/dev/null 2>&1 && notify-send "Self Shell" "$1" || true
}

check_update() {
  local force="${1:-false}" mode days now last elapsed remote_count remote_url fetch_url
  mode="$(read_mode)"
  days="$(read_days)"
  [[ "$force" == true || "$mode" != off ]] || return 0

  if [[ "$force" != true && "$mode" == interval ]]; then
    now="$(date +%s)"
    last="$(jq -r '.checkedAt // 0' "$state_file" 2>/dev/null || printf 0)"
    elapsed=$((now - last))
    (( elapsed >= days * 86400 )) || return 0
  fi

  exec 9>"$lock_file"
  flock -n 9 || return 0

  remote_url="$(git -C "$repo_dir" remote get-url origin)"
  fetch_url="$remote_url"
  if [[ "$remote_url" =~ ^git@github\.com:(.+)$ ]]; then
    fetch_url="https://github.com/${BASH_REMATCH[1]}"
  elif [[ "$remote_url" =~ ^ssh://git@github\.com/(.+)$ ]]; then
    fetch_url="https://github.com/${BASH_REMATCH[1]}"
  fi

  if ! GIT_TERMINAL_PROMPT=0 timeout 45 git -C "$repo_dir" fetch --quiet \
      "$fetch_url" 'main:refs/remotes/origin/main'; then
    write_state error "Не удалось проверить GitHub"
    notify "Не удалось проверить обновления"
    return 1
  fi

  remote_count="$(git -C "$repo_dir" rev-list --count HEAD..origin/main)"
  if (( remote_count == 0 )); then
    write_state current "Установлена последняя версия"
    [[ "$force" == true ]] && notify "Установлена последняя версия"
    return 0
  fi

  if [[ -n "$(git -C "$repo_dir" status --porcelain --untracked-files=no)" ]]; then
    write_state deferred "Доступно обновление, но есть локальные изменения" "$remote_count"
    notify "Обновление отложено: есть локальные изменения"
    return 0
  fi

  if git -C "$repo_dir" merge-base --is-ancestor HEAD origin/main \
      && git -C "$repo_dir" merge --ff-only origin/main; then
    write_state updated "Обновление установлено" "$remote_count"
    notify "Обновление установлено"
  else
    write_state error "Автоматическое fast-forward обновление невозможно" "$remote_count"
    notify "Обновление требует ручного вмешательства"
    return 1
  fi
}

case "${1:-startup}" in
  status) status_json ;;
  configure)
    mode="${2:-off}"
    days="${3:-7}"
    case "$mode" in off|startup|interval) ;; *) exit 2 ;; esac
    [[ "$days" =~ ^[0-9]+$ ]] && (( days >= 1 && days <= 365 )) || exit 2
    write_config "$mode" "$days"
    status_json
    ;;
  check) check_update true ;;
  startup) check_update false ;;
  daemon)
    first_run=true
    while true; do
      mode="$(read_mode)"
      if [[ "$mode" == interval || ( "$mode" == startup && "$first_run" == true ) ]]; then
        check_update false || true
      fi
      first_run=false
      sleep 3600
    done
    ;;
  *) exit 2 ;;
esac
