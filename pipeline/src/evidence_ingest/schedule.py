from __future__ import annotations

from datetime import date


def is_due(day: date, epoch: date, interval_days: int, until: date | None = None) -> bool:
    if interval_days <= 0:
        raise ValueError("interval_days must be positive")
    if until is not None and until < epoch:
        raise ValueError("until must not be earlier than epoch")
    elapsed = (day - epoch).days
    return elapsed >= 0 and (until is None or day <= until) and elapsed % interval_days == 0
