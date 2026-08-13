#!/usr/bin/env python3

import argparse
import calendar
import datetime as dt
import json
from pathlib import Path
import sys

from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import InstalledAppFlow
from googleapiclient.discovery import build


SCOPES = ["https://www.googleapis.com/auth/calendar.readonly"]
DATA_DIR = Path.home() / ".local" / "share" / "dashboard-calendar"
TOKEN_FILE = DATA_DIR / "token.json"


def save_token(credentials: Credentials) -> None:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    TOKEN_FILE.write_text(credentials.to_json(), encoding="utf-8")
    TOKEN_FILE.chmod(0o600)


def authorize(credentials_file: Path) -> int:
    if not credentials_file.is_file():
        print(f"Файл не найден: {credentials_file}", file=sys.stderr)
        return 2

    flow = InstalledAppFlow.from_client_secrets_file(str(credentials_file), SCOPES)
    credentials = flow.run_local_server(port=0, open_browser=True)
    save_token(credentials)
    print("Google Calendar подключён в режиме только для чтения.")
    return 0


def load_credentials() -> Credentials | None:
    if not TOKEN_FILE.is_file():
        return None

    credentials = Credentials.from_authorized_user_file(str(TOKEN_FILE), SCOPES)
    if credentials.expired and credentials.refresh_token:
        credentials.refresh(Request())
        save_token(credentials)
    return credentials if credentials.valid else None


def month_range() -> tuple[dt.datetime, dt.datetime]:
    now = dt.datetime.now().astimezone()
    start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    year, month = (start.year + 1, 1) if start.month == 12 else (start.year, start.month + 1)
    return start, start.replace(year=year, month=month)


def selected_calendars(service) -> list[dict]:
    result: list[dict] = []
    page_token = None
    while True:
        response = service.calendarList().list(pageToken=page_token).execute()
        result.extend(
            item for item in response.get("items", [])
            if item.get("primary") or item.get("selected", False)
        )
        page_token = response.get("nextPageToken")
        if not page_token:
            return result


def event_time(event: dict, timezone: dt.tzinfo) -> tuple[str, str]:
    start = event.get("start", {})
    if "date" in start:
        return start["date"], ""

    value = start.get("dateTime", "")
    instant = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    local = instant.astimezone(timezone)
    return local.strftime("%Y-%m-%d"), local.strftime("%H:%M")


def sync() -> int:
    credentials = load_credentials()
    if credentials is None:
        print("AUTH_REQUIRED")
        return 0

    try:
        service = build("calendar", "v3", credentials=credentials, cache_discovery=False)
        start, end = month_range()
        events: list[dict] = []

        for google_calendar in selected_calendars(service):
            page_token = None
            while True:
                response = service.events().list(
                    calendarId=google_calendar["id"],
                    timeMin=start.isoformat(),
                    timeMax=end.isoformat(),
                    singleEvents=True,
                    orderBy="startTime",
                    maxResults=250,
                    pageToken=page_token,
                ).execute()
                for event in response.get("items", []):
                    date, time = event_time(event, start.tzinfo)
                    events.append({
                        "date": date,
                        "time": time,
                        "title": event.get("summary") or "Без названия",
                        "calendar": google_calendar.get("summary", "Google Calendar"),
                    })
                page_token = response.get("nextPageToken")
                if not page_token:
                    break

        events.sort(key=lambda event: (event["date"], event["time"], event["title"]))
        print("OK")
        print(json.dumps(events, ensure_ascii=False, separators=(",", ":")))
        return 0
    except Exception as error:
        print("ERROR")
        print(str(error), file=sys.stderr)
        return 1


def main() -> int:
    parser = argparse.ArgumentParser(description="Read-only Google Calendar backend")
    parser.add_argument("--auth", type=Path, metavar="CREDENTIALS_JSON")
    args = parser.parse_args()
    return authorize(args.auth.expanduser()) if args.auth else sync()


if __name__ == "__main__":
    raise SystemExit(main())
