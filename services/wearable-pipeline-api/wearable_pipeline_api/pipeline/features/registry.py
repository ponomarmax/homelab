from __future__ import annotations

from typing import Protocol

import pandas as pd

from .hr_window import FeatureHandlerOutput, HrWindowFeatureBuilder


class FeatureHandler(Protocol):
    name: str

    def handle(self, clean_df: pd.DataFrame, run_id: str, input_artifact_reference: str) -> FeatureHandlerOutput:
        pass


HandlerKey = tuple[str, str, str]


def feature_handler_registry() -> dict[HandlerKey, FeatureHandler]:
    return {
        ("polar", "verity_sense", "hr"): HrWindowFeatureBuilder(),
    }
