#!/usr/bin/env bash

set -euo pipefail

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/self-shell/command-center-thumbnails"
mkdir -p "$cache_dir"

find "$HOME/Pictures" "$HOME/Videos" -maxdepth 1 -type f \
  \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \
     -o -iname '*.mp4' -o -iname '*.mkv' \) \
  -printf '%T@|%p\n' 2>/dev/null \
  | sort -rn \
  | head -12 \
  | cut -d'|' -f2- \
  | while IFS= read -r media_path; do
      cache_key="$(printf '%s' "$media_path" | sha256sum | cut -d' ' -f1)"
      thumbnail="$cache_dir/${cache_key}.jpg"

      if [[ ! -f "$thumbnail" || "$media_path" -nt "$thumbnail" ]]; then
        temporary="${thumbnail}.tmp.jpg"
        if ffmpeg -loglevel error -y -i "$media_path" \
          -vf 'thumbnail,scale=480:270:force_original_aspect_ratio=increase,crop=480:270' \
          -frames:v 1 -q:v 4 "$temporary" 2>/dev/null; then
          mv -f -- "$temporary" "$thumbnail"
        else
          rm -f -- "$temporary"
          continue
        fi
      fi

      printf '%s\t%s\n' "$media_path" "$thumbnail"
    done
