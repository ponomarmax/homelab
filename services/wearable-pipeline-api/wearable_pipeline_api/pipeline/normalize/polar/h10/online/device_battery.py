from __future__ import annotations

from typing import Any

from ...common.base import BASE_COLUMNS
from .common import H10OnlineEventNormalizer, H10OnlineEventPolicy

BATTERY_COLUMNS = BASE_COLUMNS + [
    "level_percent",
    "charge_state",
    "power_sources",
    "event_type",
    "sdk_raw",
]


def _battery_fields(payload: dict[str, Any], chunk: dict[str, Any]) -> dict[str, Any] | None:
    battery = payload.get("battery") if isinstance(payload.get("battery"), dict) else {}
    sample_ts = payload.get("received_at_collector") or chunk.get("received_at_collector")
    level_percent = payload.get("level_percent")
    if level_percent is None:
        level_percent = battery.get("level_percent")
    if not sample_ts or level_percent is None:
        return None

    charge_state = payload.get("charge_state")
    if charge_state is None:
        charge_state = battery.get("charge_state")
    power_sources = payload.get("power_sources")
    if not isinstance(power_sources, list):
        power_sources = battery.get("power_sources")
    if not isinstance(power_sources, list):
        power_sources = []

    return {
        "__sample_ts": sample_ts,
        "level_percent": float(level_percent),
        "charge_state": charge_state,
        "power_sources": power_sources,
        "event_type": payload.get("event_type"),
        "sdk_raw": payload.get("sdk_raw"),
    }


BATTERY_POLICY = H10OnlineEventPolicy(
    payload_schema="polar.device_battery",
    stream_type="battery",
    report_confidence="high",
    report_alignment_basis="payload.received_at_collector",
    row_columns=BATTERY_COLUMNS,
    payload_to_fields=_battery_fields,
)


class PolarDeviceBatteryNormalizer(H10OnlineEventNormalizer):
    name = "PolarDeviceBatteryNormalizer"
    payload_schema = "polar.device_battery"

    def __init__(self) -> None:
        super().__init__(name=self.name, policy=BATTERY_POLICY)
