from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Callable

import pandas as pd

from ....common.policies import BaseStreamPolicy
from ..alignment import StreamSpec
from ..stream_fields import (
    build_acc_fields,
    build_gyro_fields,
    build_hr_fields,
    build_mag_fields,
    build_ppg_fields,
    build_ppi_fields,
    ppi_step_seconds,
)


@dataclass(frozen=True)
class VeritySenseOfflineStreamPolicy(BaseStreamPolicy):
    spec: StreamSpec
    default_rate_hz: float
    cadence_anchor: str
    uses_invalid_zero_timestamp_repair: bool
    field_builder: Callable[[dict[str, Any]], dict[str, Any]]
    build_timestamp_candidates: Callable[[list[dict[str, Any]], str | None, Callable[[int], Any]], dict[int, Any]]
    repair_missing_timestamp: Callable[[int, dict[str, Any], dict[int, Any], float], Any | None]


def _no_candidates(_samples: list[dict[str, Any]], _time_field: str | None, _resolve: Callable[[int], Any]) -> dict[int, Any]:
    return {}


def _no_repair(_idx: int, _sample: dict[str, Any], _candidates: dict[int, Any], _stream_rate_hz: float) -> Any | None:
    return None


def _ppi_candidates(samples: list[dict[str, Any]], time_field: str | None, resolve: Callable[[int], Any]) -> dict[int, Any]:
    if not time_field:
        return {}
    out: dict[int, Any] = {}
    for idx, sample in enumerate(samples):
        if not isinstance(sample, dict):
            continue
        raw_ts = sample.get(time_field)
        if isinstance(raw_ts, int) and raw_ts > 0:
            parsed = resolve(int(raw_ts))
            if parsed is not None:
                out[idx] = parsed
    return out


def _ppi_repair(idx: int, sample: dict[str, Any], candidates: dict[int, Any], stream_rate_hz: float) -> Any | None:
    if idx in candidates:
        return candidates[idx]
    prev_idx = max((k for k in candidates.keys() if k < idx), default=None)
    next_idx = min((k for k in candidates.keys() if k > idx), default=None)
    if prev_idx is not None and next_idx is not None and next_idx > prev_idx:
        prev_ts = candidates[prev_idx]
        next_ts = candidates[next_idx]
        fraction = float(idx - prev_idx) / float(next_idx - prev_idx)
        return prev_ts + (next_ts - prev_ts) * fraction
    if prev_idx is not None:
        step = ppi_step_seconds(sample, stream_rate_hz)
        return candidates[prev_idx] + pd.to_timedelta(step * (idx - prev_idx), unit="s")
    if next_idx is not None:
        step = ppi_step_seconds(sample, stream_rate_hz)
        return candidates[next_idx] - pd.to_timedelta(step * (next_idx - idx), unit="s")
    return None


HR_POLICY = VeritySenseOfflineStreamPolicy(
    payload_schema="polar.offline.hr",
    stream_type="hr",
    report_confidence="low",
    report_alignment_basis="offline_policy_managed",
    row_columns=[],
    spec=StreamSpec(stream_type="hr", payload_schema="polar.offline.hr", time_field=None),
    default_rate_hz=1.0,
    cadence_anchor="end",
    uses_invalid_zero_timestamp_repair=False,
    field_builder=build_hr_fields,
    build_timestamp_candidates=_no_candidates,
    repair_missing_timestamp=_no_repair,
)

PPI_POLICY = VeritySenseOfflineStreamPolicy(
    payload_schema="polar.offline.ppi",
    stream_type="ppi",
    report_confidence="low",
    report_alignment_basis="offline_policy_managed",
    row_columns=[],
    spec=StreamSpec(stream_type="ppi", payload_schema="polar.offline.ppi", time_field="timeStamp"),
    default_rate_hz=1.0,
    cadence_anchor="start",
    uses_invalid_zero_timestamp_repair=True,
    field_builder=build_ppi_fields,
    build_timestamp_candidates=_ppi_candidates,
    repair_missing_timestamp=_ppi_repair,
)

ACC_POLICY = VeritySenseOfflineStreamPolicy(
    payload_schema="polar.offline.acc",
    stream_type="acc",
    report_confidence="low",
    report_alignment_basis="offline_policy_managed",
    row_columns=[],
    spec=StreamSpec(stream_type="acc", payload_schema="polar.offline.acc", time_field="timeStamp"),
    default_rate_hz=52.0,
    cadence_anchor="start",
    uses_invalid_zero_timestamp_repair=False,
    field_builder=build_acc_fields,
    build_timestamp_candidates=_no_candidates,
    repair_missing_timestamp=_no_repair,
)

GYRO_POLICY = VeritySenseOfflineStreamPolicy(
    payload_schema="polar.offline.gyro",
    stream_type="gyro",
    report_confidence="low",
    report_alignment_basis="offline_policy_managed",
    row_columns=[],
    spec=StreamSpec(stream_type="gyro", payload_schema="polar.offline.gyro", time_field="timeStamp"),
    default_rate_hz=52.0,
    cadence_anchor="start",
    uses_invalid_zero_timestamp_repair=False,
    field_builder=build_gyro_fields,
    build_timestamp_candidates=_no_candidates,
    repair_missing_timestamp=_no_repair,
)

MAG_POLICY = VeritySenseOfflineStreamPolicy(
    payload_schema="polar.offline.mag",
    stream_type="mag",
    report_confidence="low",
    report_alignment_basis="offline_policy_managed",
    row_columns=[],
    spec=StreamSpec(stream_type="mag", payload_schema="polar.offline.mag", time_field="timeStamp"),
    default_rate_hz=50.0,
    cadence_anchor="start",
    uses_invalid_zero_timestamp_repair=False,
    field_builder=build_mag_fields,
    build_timestamp_candidates=_no_candidates,
    repair_missing_timestamp=_no_repair,
)

PPG_POLICY = VeritySenseOfflineStreamPolicy(
    payload_schema="polar.offline.ppg",
    stream_type="ppg",
    report_confidence="low",
    report_alignment_basis="offline_policy_managed",
    row_columns=[],
    spec=StreamSpec(stream_type="ppg", payload_schema="polar.offline.ppg", time_field="timeStamp"),
    default_rate_hz=55.0,
    cadence_anchor="start",
    uses_invalid_zero_timestamp_repair=False,
    field_builder=build_ppg_fields,
    build_timestamp_candidates=_no_candidates,
    repair_missing_timestamp=_no_repair,
)

POLICY_BY_SCHEMA = {
    "polar.offline.hr": HR_POLICY,
    "polar.offline.ppi": PPI_POLICY,
    "polar.offline.acc": ACC_POLICY,
    "polar.offline.gyro": GYRO_POLICY,
    "polar.offline.mag": MAG_POLICY,
    "polar.offline.ppg": PPG_POLICY,
}

# Backward-compatible alias
StreamPolicy = VeritySenseOfflineStreamPolicy
