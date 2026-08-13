#!/usr/bin/env bash

set -euo pipefail

api_url="http://127.0.0.1:2017/api/touch"
token=""

shopt -s nullglob
token_databases=(
  "${HOME}"/.mozilla/firefox/*/storage/default/http+++localhost+2017/ls/data.sqlite
  "${HOME}"/.mozilla/firefox/*/storage/default/http+++127.0.0.1+2017/ls/data.sqlite
)

for database in "${token_databases[@]}"; do
  [[ -r "$database" ]] || continue
  token="$(
    sqlite3 "file:${database}?immutable=1" \
      "SELECT CAST(value AS TEXT) FROM data WHERE key = 'token' LIMIT 1;" \
      2>/dev/null || true
  )"
  [[ -n "$token" ]] && break
done

response=""
if [[ -n "$token" ]]; then
  response="$(
    curl --silent --show-error --max-time 3 \
      --header "Authorization: ${token}" \
      "$api_url" 2>/dev/null || true
  )"
fi

if [[ "$(jq -r '.code // empty' <<< "$response" 2>/dev/null)" == "SUCCESS" ]]; then
  connection="$(
    jq -c '
      (.data.touch.connectedServer // []) as $connections
      | ($connections | map(select(.outbound == "proxy"))[0] // $connections[0] // empty)
    ' <<< "$response" 2>/dev/null || true
  )"

  if [[ -n "$connection" ]]; then
    active_name="$(
      jq -r --argjson connection "$connection" '
        if $connection._type == "server" then
          (.data.touch.servers // [])[]
          | select(.id == $connection.id)
          | .name
        else
          (.data.touch.subscriptions // [])[]
          | select(.id == ($connection.sub // $connection.id))
          | ((.servers // [])[] | select(.id == $connection.id) | .name) // .host // .address
        end
      ' <<< "$response" 2>/dev/null | head -n1
    )"
    active_name="${active_name:-Активное подключение}"
    if [[ "${WAYBAR_COMPACT:-0}" == "1" ]]; then icon=""; else icon="  "; fi
    jq -cn --arg text "$icon" --arg tooltip "V2RayA подключён: ${active_name}" \
      '{text: $text, tooltip: $tooltip, class: "online"}'
    exit 0
  fi

  if [[ "${WAYBAR_COMPACT:-0}" == "1" ]]; then icon=""; else icon="  "; fi
  jq -cn --arg text "$icon" \
    '{text: $text, tooltip: "V2RayA запущен, сервер не подключён", class: "offline"}'
  exit 0
fi

if [[ "${WAYBAR_COMPACT:-0}" == "1" ]]; then icon=""; else icon="  "; fi
jq -cn --arg text "$icon" \
  '{text: $text, tooltip: "Не удалось получить статус V2RayA", class: "offline"}'
