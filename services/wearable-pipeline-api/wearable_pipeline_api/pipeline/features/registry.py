from __future__ import annotations

from typing import Protocol

import pandas as pd

from .acc_window import AccWindowFeatureBuilder
from .battery_window import BatteryWindowFeatureBuilder
from .ecg_window import EcgWindowFeatureBuilder
from .hr_window import FeatureHandlerOutput, HrWindowFeatureBuilder


class FeatureHandler(Protocol):
    name: str

    def handle(self, clean_df: pd.DataFrame, run_id: str, input_artifact_reference: str) -> FeatureHandlerOutput:
        pass


HandlerKey = tuple[str, str, str]


def feature_handler_registry() -> dict[HandlerKey, FeatureHandler]:
    return {
        ("polar", "h10", "polar.hr"): HrWindowFeatureBuilder(),
        ("polar", "h10", "polar.acc"): AccWindowFeatureBuilder(),
        ("polar", "h10", "polar.ecg"): EcgWindowFeatureBuilder(),
        ("polar", "h10", "polar.device_battery"): BatteryWindowFeatureBuilder(),
        ("polar", "verity_sense", "polar.hr"): HrWindowFeatureBuilder(),
    }
