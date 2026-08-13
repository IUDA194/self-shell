#!/usr/bin/env python3

from __future__ import annotations

import os
import re
import shlex
import subprocess
import sys
from pathlib import Path


ANSI_RE = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]")

KEY = "\x1b[1m\x1b[38;2;186;148;95m"
TITLE = "\x1b[1m\x1b[38;2;204;194;183m"
OUTPUT = "\x1b[38;2;204;194;183m"
SEPARATOR = "\x1b[38;2;116;105;97m"
SUCCESS = "\x1b[32m"
WARN = "\x1b[93m"
ERROR = "\x1b[91m"
RESET = "\x1b[0m"


def strip_ansi(text: str) -> str:
    return ANSI_RE.sub("", text)


def run_command(command: list[str]) -> str:
    result = subprocess.run(command, capture_output=True, text=True, check=False)
    if result.returncode != 0:
        sys.stderr.write(result.stderr)
        raise SystemExit(result.returncode)
    return result.stdout


def visible_width(line: str) -> int:
    return len(strip_ansi(line))


def colorize_percentages(text: str) -> str:
    def repl(match: re.Match[str]) -> str:
        value = int(match.group(1))
        color = SUCCESS if value < 60 else WARN if value < 80 else ERROR
        return f"({color}{value}%{OUTPUT})"

    return re.sub(r"\((\d{1,3})%\)", repl, text)


def colorize_line(line: str) -> str:
    plain = strip_ansi(line)

    if not plain:
        return ""

    line = plain

    if set(line) == {"─"}:
        return f"{SEPARATOR}{line}{RESET}"

    if "@" in line and ":" not in line:
        user, host = line.split("@", 1)
        return f"{KEY}{user}{RESET}{SEPARATOR}@{RESET}{TITLE}{host}{RESET}"

    if ":" in line:
        key, value = line.split(":", 1)
        return f"{KEY}{key}{RESET}{SEPARATOR}:{RESET}{OUTPUT}{colorize_percentages(value)}{RESET}"

    return f"{OUTPUT}{line}{RESET}"


def main() -> int:
    config = Path.home() / ".config/fastfetch/config.jsonc"
    wallpaper = Path(
        os.environ.get(
            "FASTFETCH_WALLPAPER",
            str(Path.home() / "Pictures" / "Wallpapers" / "fastfetch" / "logo120.jpg"),
        )
    ).expanduser()

    if not wallpaper.is_file():
        sys.stderr.write(
            f"Wallpaper not found: {wallpaper}\n"
            "Set FASTFETCH_WALLPAPER to an existing image.\n"
        )
        return 1

    chafa_output = run_command(
        [
            "chafa",
            "--format",
            "symbols",
            "--colors",
            "full",
            "--size",
            "120x121",
            "--symbols",
            "block+border+space-wide-inverted",
            "--color-space",
            "din99d",
            "--dither",
            "ordered",
            "--exact-size",
            "on",
            "--relative",
            "off",
            "--polite",
            "on",
            "--optimize",
            "9",
            "--work",
            "9",
            str(wallpaper),
        ]
    )

    fastfetch_args = [
        "command",
        "fastfetch",
        "--config",
        str(config),
        "--logo",
        "none",
        "--pipe",
        "true",
        *sys.argv[1:],
    ]
    fastfetch_output = run_command(
        [
            os.environ.get("SHELL", "fish"),
            "-lc",
            shlex.join(fastfetch_args),
        ]
    )

    left_lines = chafa_output.rstrip("\n").splitlines()
    right_lines = [colorize_line(line) for line in fastfetch_output.rstrip("\n").splitlines()]
    left_width = max((visible_width(line) for line in left_lines), default=0)
    gap = " " * 4
    total_lines = max(len(left_lines), len(right_lines))

    for index in range(total_lines):
        left = left_lines[index] if index < len(left_lines) else ""
        right = right_lines[index] if index < len(right_lines) else ""
        padding = " " * max(0, left_width - visible_width(left))
        sys.stdout.write(f"{left}{padding}{gap}{right}\n")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
