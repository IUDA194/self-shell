#!/usr/bin/env bash

set -euo pipefail

videos="${HOME}/Videos"
state_dir="${XDG_RUNTIME_DIR:-/tmp}/self-shell-command-center"
recording_state="$state_dir/recording"
night_state="$state_dir/night-light"
caffeine_state="$state_dir/caffeine"
mkdir -p "$videos"
mkdir -p "$state_dir"

remember_recording() {
  local recorder_pid="$1" output_file="$2"
  printf '%s\t%s\t%s\n' "$recorder_pid" "$(date +%s)" "$output_file" >"$recording_state"
}

case "${1:-}" in
  caffeine)
    if [[ -r "$caffeine_state" ]]; then
      caffeine_pid="$(cat "$caffeine_state")"
      if [[ "$caffeine_pid" =~ ^[0-9]+$ ]]; then
        kill "$caffeine_pid" 2>/dev/null || true
      fi
      rm -f -- "$caffeine_state"
      notify-send "Кофеин выключен" "Автоматический сон снова разрешён"
    elif command -v systemd-inhibit >/dev/null 2>&1; then
      systemd-inhibit --what=idle:sleep --mode=block --who="Self Shell" \
        --why="Режим Кофеин включён" sleep infinity >/dev/null 2>&1 &
      printf '%s\n' "$!" > "$caffeine_state"
      hyprctl dispatch dpms on >/dev/null 2>&1 || true
      notify-send "Кофеин включён" "Экран и система не будут переходить в сон"
    else
      notify-send "Кофеин" "systemd-inhibit недоступен"
      exit 1
    fi
    ;;
  caffeine-status)
    if [[ -r "$caffeine_state" ]]; then
      caffeine_pid="$(cat "$caffeine_state")"
      if [[ "$caffeine_pid" =~ ^[0-9]+$ ]] && kill -0 "$caffeine_pid" 2>/dev/null; then
        printf '1\n'
        exit 0
      fi
      rm -f -- "$caffeine_state"
    fi
    printf '0\n'
    ;;
  night-light)
    if [[ -e "$night_state" ]]; then
      hyprctl hyprsunset temperature 6000 >/dev/null
      rm -f "$night_state"
    elif "$HOME/.config/hypr/brightness.sh" ensure; then
      hyprctl hyprsunset temperature 4500 >/dev/null
      : >"$night_state"
    else
      notify-send "Night Light" "Установите пакет hyprsunset"
    fi
    ;;
  record)
    file="$videos/recording_$(date +%Y-%m-%d_%H-%M-%S).mp4"
    wf-recorder -f "$file" >/dev/null 2>&1 &
    remember_recording "$!" "$file"
    notify-send "Запись экрана" "Запись началась"
    ;;
  record-region)
    sleep 0.55
    geometry="$(slurp)" || exit 0
    file="$videos/recording_$(date +%Y-%m-%d_%H-%M-%S).mp4"
    wf-recorder -g "$geometry" -f "$file" >/dev/null 2>&1 &
    remember_recording "$!" "$file"
    notify-send "Запись области" "Запись началась"
    ;;
  stop-record)
    pkill -INT -x wf-recorder || exit 0
    rm -f "$recording_state"
    notify-send "Запись экрана" "Запись сохранена в ~/Videos"
    ;;
  record-status)
    if ! pgrep -x wf-recorder >/dev/null; then
      rm -f "$recording_state"
      printf '0\t0\t0\t\n'
      exit 0
    fi
    if [[ -r "$recording_state" ]]; then
      IFS=$'\t' read -r recorder_pid started_at output_file <"$recording_state"
      elapsed=$(( $(date +%s) - started_at ))
      size="$(stat -c %s "$output_file" 2>/dev/null || printf 0)"
      printf '1\t%s\t%s\t%s\n' "$elapsed" "$size" "$output_file"
    else
      printf '1\t0\t0\t\n'
    fi
    ;;
  ocr)
    sleep 0.55
    if ! command -v tesseract >/dev/null; then
      notify-send "OCR" "Установите Tesseract OCR"
      exit 1
    fi
    geometry="$(slurp)" || exit 0
    available_languages="$(tesseract --list-langs 2>/dev/null)"
    if grep -qx rus <<<"$available_languages" && grep -qx eng <<<"$available_languages"; then
      ocr_languages="rus+eng"
    elif grep -qx rus <<<"$available_languages"; then
      ocr_languages="rus"
    elif grep -qx eng <<<"$available_languages"; then
      ocr_languages="eng"
    else
      notify-send "OCR" "Не установлены языковые данные rus или eng"
      exit 1
    fi
    source_image="$(mktemp --tmpdir="${XDG_RUNTIME_DIR:-/tmp}" self-shell-ocr-source-XXXXXX.png)"
    prepared_image="$(mktemp --tmpdir="${XDG_RUNTIME_DIR:-/tmp}" self-shell-ocr-prepared-XXXXXX.png)"
    trap 'rm -f -- "$source_image" "$prepared_image"' EXIT
    grim -g "$geometry" "$source_image"
    ffmpeg -loglevel error -y -i "$source_image" \
      -vf 'scale=iw*2:ih*2:flags=lanczos,format=gray,eq=contrast=1.35:brightness=0.03,unsharp=5:5:0.8:3:3:0.4' \
      "$prepared_image"
    text="$(tesseract "$prepared_image" stdout -l "$ocr_languages" --psm 6 2>/dev/null || true)"
    text="$(printf '%s' "$text" | sed -e 's/[[:space:]]\+$//' -e '/./,$!d')"
    [[ -n "$text" ]] || { notify-send "OCR" "Текст не найден"; exit 0; }
    printf '%s' "$text" | wl-copy --type 'text/plain;charset=utf-8'
    preview="$(printf '%s' "$text" | tr '\n' ' ' | cut -c1-100)"
    notify-send "OCR · скопировано" "$preview"
    ;;
esac
