#!/usr/bin/env python3
"""Read cached agent quotas without accessing credentials or starting agents."""
import json
import os
from datetime import datetime
from pathlib import Path


def row(name, description):
    return dict(name=name, description=description, kind="action", mode="ai",
                symbol="󰚩", icon="applications-development")


def collect(home):
    rows = []
    codex = Path(os.environ.get("CODEX_HOME", home / ".codex"))
    if codex.is_dir():
        latest = {}
        # Bound IO: recent session tails contain the latest quota snapshots.
        files = sorted((codex / "sessions").glob("**/*.jsonl"),
                       key=lambda p: p.stat().st_mtime, reverse=True)[:20]
        for path in files:
            try:
                with path.open("rb") as stream:
                    stream.seek(max(0, path.stat().st_size - 512 * 1024))
                    lines = stream.read().splitlines()
                for line in lines:
                    if b'"rate_limits"' not in line:
                        continue
                    try:
                        event = json.loads(line)
                        limits = event.get("payload", {}).get("rate_limits")
                        stamp = event.get("timestamp", "")
                        if not isinstance(limits, dict):
                            continue
                        key = limits.get("limit_id") or "codex"
                        if stamp > latest.get(key, ("", {}))[0]:
                            latest[key] = (stamp, limits)
                    except (ValueError, TypeError):
                        continue
            except OSError:
                continue
        for key, (stamp, limits) in latest.items():
            for period in ("primary", "secondary"):
                window = limits.get(period)
                if not isinstance(window, dict) or window.get("used_percent") is None:
                    continue
                minutes = window.get("window_minutes", 0)
                label = f"{minutes // 1440} д." if minutes >= 1440 else f"{minutes / 60:g} ч."
                reset = window.get("resets_at")
                reset_time = datetime.fromtimestamp(reset).astimezone() if reset else None
                expired = reset_time and reset_time.timestamp() <= datetime.now().timestamp()
                remaining = max(0, min(100, 100 - float(window["used_percent"])))
                title = f"Codex · {label}" + (f" · {key}" if key != "codex" else "")
                detail = "Сброс: " + (reset_time.strftime("%d.%m %H:%M") if reset_time else "неизвестно")
                detail += " · данные сеанса " + stamp[:16].replace("T", " ") + " UTC"
                rows.append(dict(row(title, detail), remaining=None if expired else remaining))
        if not rows:
            rows.append(row("Codex", "Нет данных о лимитах — выполните запрос в Codex"))
    return rows or [row("Лимиты недоступны", "Нет локальных данных о квотах")]


if __name__ == "__main__":
    try:
        print(json.dumps(collect(Path.home()), ensure_ascii=False))
    except (OSError, ValueError, TypeError):
        print(json.dumps([row("Лимиты недоступны", "Не удалось прочитать данные агентов")], ensure_ascii=False))
