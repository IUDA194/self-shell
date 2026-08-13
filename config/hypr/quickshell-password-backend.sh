#!/usr/bin/env bash
set -euo pipefail

store="${PASSWORD_STORE_DIR:-${HOME}/.password-store}"

list_entries() {
    [[ -d "$store" ]] || exit 0
    find -L "$store" -type f -name '*.gpg' -printf '%P\n' \
        | sed 's/\.gpg$//' \
        | LC_ALL=C sort -f
}

valid_entry() {
    local entry="$1"
    [[ -n "$entry" && "$entry" != /* && "$entry" != *'..'* && -f "$store/$entry.gpg" ]]
}

copy_password() {
    local entry="$1" secret
    valid_entry "$entry" || exit 2
    secret="$(PASSWORD_STORE_DIR="$store" pass show "$entry" | head -n 1)"
    [[ -n "$secret" ]] || exit 3
    printf '%s' "$secret" | wl-copy --trim-newline
    notify-send -a "Passwords" -i dialog-password \
        "Пароль скопирован" "${entry##*/} · буфер очистится через 45 секунд"

    (
        sleep 45
        if [[ "$(wl-paste --no-newline 2>/dev/null || true)" == "$secret" ]]; then
            wl-copy --clear
        fi
    ) >/dev/null 2>&1 &
}

autotype_entry() {
    local entry="$1" content password username
    valid_entry "$entry" || exit 2
    content="$(PASSWORD_STORE_DIR="$store" pass show "$entry")"
    password="${content%%$'\n'*}"
    username="$(
        printf '%s\n' "$content" \
            | sed -nE 's/^(user(name)?|login):[[:space:]]*//Ip' \
            | head -n 1
    )"
    # Most pass stores encode the login in the entry name (service/login).
    # An explicit metadata field above always takes priority.
    username="${username:-${entry##*/}}"
    [[ -n "$password" ]] || exit 3

    # Give the Quickshell overlay enough time to close and restore focus.
    sleep 0.35
    printf '%s' "$username" | wtype -d 12 -
    wtype -P Tab -p Tab
    printf '%s' "$password" | wtype -d 12 -
    notify-send -a "Passwords" -i dialog-password \
        "Данные успешно введены" "${entry##*/}"
}

case "${1:-}" in
    --list)
        list_entries
        ;;
    --copy)
        [[ $# -eq 2 ]] || exit 2
        copy_password "$2"
        ;;
    --autotype)
        [[ $# -eq 2 ]] || exit 2
        autotype_entry "$2"
        ;;
    *)
        exit 2
        ;;
esac
