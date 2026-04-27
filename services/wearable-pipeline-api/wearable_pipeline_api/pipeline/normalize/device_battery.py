from __future__ import annotations

from pathlib import Path
from typing import Any

from .base import BASE_COLUMNS, NormalizeHandlerOutput, finalize_rows, parse_jsonl_chunks

BATTERY_COLUMNS = BASE_COLUMNS + [
    "level_percent",
    "charge_state",
    "power_sources",
    "event_type",
    "sdk_raw",
]


class PolarDeviceBatteryNormalizer:
    name = "PolarDeviceBatteryNormalizer"
    payload_schema = "polar.device_battery"

    def handle(self, raw_path: Path) -> NormalizeHandlerOutput:
        rows: list[dict[str, Any]] = []
        chunks, warnings = parse_jsonl_chunks(raw_path)
        skipped_chunks_count = 0
        chunks_count = 0

        session_id = ""
        stream_id = ""
        user_id = ""

        for chunk in chunks:
            line_number = int(chunk.get("__line_number") or 0)
            payload_schema = str(((chunk.get("transport") or {}).get("payload_schema") or "")).strip().lower()
            if payload_schema != self.payload_schema:
                continue

            chunks_count += 1
            session_id = str(chunk.get("session_id") or session_id)
            stream_id = str(chunk.get("stream_id") or stream_id)
            user_id = str(chunk.get("user_id") or user_id)

            source = chunk.get("source") if isinstance(chunk.get("source"), dict) else {}
            collection = chunk.get("collection") if isinstance(chunk.get("collection"), dict) else {}
            time_info = chunk.get("time") if isinstance(chunk.get("time"), dict) else {}
            server = chunk.get("server") if isinstance(chunk.get("server"), dict) else {}
            payload = chunk.get("payload") if isinstance(chunk.get("payload"), dict) else {}
            battery = payload.get("battery") if isinstance(payload.get("battery"), dict) else {}

            sample_ts = payload.get("received_at_collector") or chunk.get("received_at_collector")
            level_percent = payload.get("level_percent")
            if level_percent is None:
                level_percent = battery.get("level_percent")
            if not sample_ts or level_percent is None:
                skipped_chunks_count += 1
                warnings.append(f"line {line_number}: missing required battery fields")
                continue

            charge_state = payload.get("charge_state")
            if charge_state is None:
                charge_state = battery.get("charge_state")
            power_sources = payload.get("power_sources")
            if not isinstance(power_sources, list):
                power_sources = battery.get("power_sources")

            rows.append(
                {
                    "ts_utc": sample_ts,
                    "received_at_collector": sample_ts,
                    "uploaded_at_collector": time_info.get("uploaded_at_collector"),
                    "received_at_server": server.get("received_at_server"),
                    "session_id": chunk.get("session_id"),
                    "stream_id": chunk.get("stream_id"),
                    "stream_type": chunk.get("stream_type"),
                    "payload_schema": payload_schema,
                    "user_id": str(chunk.get("user_id") or ""),
                    "source_vendor": source.get("vendor"),
                    "source_device_model": source.get("device_model"),
                    "source_device_id": source.get("device_id"),
                    "collection_mode": collection.get("mode"),
                    "source_chunk_id": chunk.get("chunk_id"),
                    "source_sequence": chunk.get("sequence"),
                    "source_line_number": line_number,
                    "alignment_confidence": "high",
                    "level_percent": float(level_percent),
                    "charge_state": charge_state,
                    "power_sources": power_sources if isinstance(power_sources, list) else [],
                    "event_type": payload.get("event_type"),
                    "sdk_raw": payload.get("sdk_raw"),
                }
            )

        df = finalize_rows(rows, columns=BATTERY_COLUMNS)
        report = {
            "session_id": session_id,
            "stream_id": stream_id,
            "stream_type": "device_battery",
            "payload_schema": self.payload_schema,
            "user_id": user_id,
            "alignment_basis": "payload.received_at_collector",
            "confidence": "high",
            "samples_count": int(len(df.index)),
            "chunks_count": chunks_count,
            "skipped_chunks_count": skipped_chunks_count,
            "warnings": warnings,
        }
        return NormalizeHandlerOutput(dataframe=df, report=report, warnings=warnings)
