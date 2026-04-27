from __future__ import annotations

import re


def canonicalize_device_model(value: str) -> str:
    raw = str(value or "").strip().lower()
    if not raw:
        return ""

    # Keep alphanumeric characters and treat separators uniformly.
    compact = re.sub(r"[^a-z0-9]+", " ", raw).strip()
    tokenized = compact.replace(" ", "")

    if tokenized in {"polarh10", "h10"}:
        return "h10"
    if tokenized in {"polarveritysense", "veritysense"}:
        return "verity_sense"

    return compact.replace(" ", "_")
