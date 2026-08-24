#!/usr/bin/env python3

import json
import locale
import os
from pathlib import Path
import sys

ROOT = Path.home() / ".config" / "self-shell" / "config" / "locales"


def language() -> str:
    value = (os.getenv("SELF_SHELL_LANG") or os.getenv("LC_ALL") or
             os.getenv("LC_MESSAGES") or os.getenv("LANG") or
             locale.getlocale()[0] or "ru")
    return value.split(".")[0].split("_")[0].split("-")[0].lower()


def load(code: str) -> dict[str, str]:
    path = ROOT / f"{code}.json"
    if not path.is_file():
        path = ROOT / "ru.json"
    return json.loads(path.read_text(encoding="utf-8"))


def main() -> int:
    if len(sys.argv) < 2:
        return 2
    fallback = load("ru")
    selected = load(language())
    value = selected.get(sys.argv[1], fallback.get(sys.argv[1], sys.argv[1]))
    for index, replacement in enumerate(sys.argv[2:]):
        value = value.replace("{" + str(index) + "}", replacement)
    print(value)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
