from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any

import pandas as pd

from wearable_pipeline_api.pipeline.normalize import PolarHrNormalizer


@dataclass
class HrNormalizationResult:
    dataframe: pd.DataFrame
    report: dict[str, Any]


class HrNormalizer:
    def __init__(self) -> None:
        self._handler = PolarHrNormalizer()

    def normalize(self, raw_path: Path) -> HrNormalizationResult:
        output = self._handler.handle(raw_path)
        return HrNormalizationResult(dataframe=output.dataframe, report=output.report)
