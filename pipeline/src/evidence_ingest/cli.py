from __future__ import annotations

import argparse
import json
from datetime import date, datetime
from pathlib import Path
from zoneinfo import ZoneInfo

from .collect import collect_profile, write_public_snapshot
from .pipeline import process_file
from .projection import write_outputs
from .schedule import is_due


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Deterministic evidence-document ingestion")
    subparsers = parser.add_subparsers(dest="command", required=True)

    inspect = subparsers.add_parser("inspect", help="Classify, extract and project one local file")
    inspect.add_argument("input", type=Path)
    inspect.add_argument("--institution", required=True)
    inspect.add_argument("--source-id", required=True)
    inspect.add_argument("--expected-term", action="append", default=[])
    inspect.add_argument("--out", type=Path, required=True)

    collect = subparsers.add_parser("collect", help="Collect every enabled public target in one profile")
    collect.add_argument("--profile", type=Path, required=True)
    collect.add_argument("--out", type=Path, required=True)
    collect.add_argument("--timeout", type=int, default=45)
    collect.add_argument("--public-archive", type=Path)
    collect.add_argument("--snapshot-date", type=date.fromisoformat)
    collect.add_argument("--timezone", default="Asia/Seoul")

    due = subparsers.add_parser("due", help="Return whether a date is on an exact N-day cadence")
    due.add_argument("--epoch", type=date.fromisoformat, required=True)
    due.add_argument("--date", dest="day", type=date.fromisoformat)
    due.add_argument("--timezone", default="Asia/Seoul")
    due.add_argument("--interval-days", type=int, default=10)
    due.add_argument("--until", type=date.fromisoformat)
    return parser


def main() -> int:
    args = _parser().parse_args()
    if args.command == "inspect":
        result, normalized_text = process_file(
            args.input,
            institution_id=args.institution,
            source_id=args.source_id,
            expected_terms=tuple(args.expected_term),
        )
        paths = write_outputs(result, normalized_text, args.out)
        print(json.dumps({key: str(path) for key, path in paths.items()}, ensure_ascii=False, sort_keys=True))
        return 0
    if args.command == "collect":
        index = collect_profile(args.profile, args.out, timeout=args.timeout)
        response: dict = {"collection": index}
        if args.public_archive:
            snapshot_day = args.snapshot_date or datetime.now(ZoneInfo(args.timezone)).date()
            response["public_snapshot"] = str(
                write_public_snapshot(index, args.public_archive, snapshot_day.isoformat())
            )
        print(json.dumps(response, ensure_ascii=False, sort_keys=True))
        return 1 if index["failures"] else 0
    if args.command == "due":
        day = args.day or datetime.now(ZoneInfo(args.timezone)).date()
        print("true" if is_due(day, args.epoch, args.interval_days, args.until) else "false")
        return 0
    raise AssertionError(f"Unknown command: {args.command}")


if __name__ == "__main__":
    raise SystemExit(main())
