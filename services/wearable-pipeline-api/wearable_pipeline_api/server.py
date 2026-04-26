from __future__ import annotations

import argparse
import logging
from pathlib import Path

from fastapi import FastAPI

from .config.settings import HEALTH_PATH, SERVICE_NAME, Settings
from .pipeline import HrPipelineRunner
from .routes import build_router
from .tracker import StateTracker

logger = logging.getLogger(__name__)


def create_app(settings: Settings) -> FastAPI:
    settings.raw_root.mkdir(parents=True, exist_ok=True)
    settings.processed_root.mkdir(parents=True, exist_ok=True)
    settings.pipeline_state_root.mkdir(parents=True, exist_ok=True)

    tracker = StateTracker(settings.pipeline_state_root)
    runner = HrPipelineRunner(
        raw_root=settings.raw_root,
        processed_root=settings.processed_root,
        tracker=tracker,
    )

    app = FastAPI(title=SERVICE_NAME, version="1.0.0")

    @app.get(HEALTH_PATH)
    async def health() -> dict[str, str]:
        return {"status": "ok", "service": SERVICE_NAME}

    app.include_router(build_router(runner))
    return app


def main(argv: list[str] | None = None) -> int:
    import uvicorn

    base = Settings.from_env()
    parser = argparse.ArgumentParser(description="Wearable pipeline API")
    parser.add_argument("--host", default=base.host)
    parser.add_argument("--port", type=int, default=base.port)
    parser.add_argument("--raw-root", default=str(base.raw_root))
    parser.add_argument("--processed-root", default=str(base.processed_root))
    parser.add_argument("--pipeline-state-root", default=str(base.pipeline_state_root))
    parser.add_argument("--log-level", default=base.log_level)
    args = parser.parse_args(argv)

    settings = Settings(
        host=args.host,
        port=args.port,
        raw_root=Path(args.raw_root),
        processed_root=Path(args.processed_root),
        pipeline_state_root=Path(args.pipeline_state_root),
        log_level=str(args.log_level).upper(),
    )

    logging.basicConfig(
        level=getattr(logging, settings.log_level, logging.INFO),
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )

    logger.info("%s listening on http://%s:%s", SERVICE_NAME, settings.host, settings.port)
    logger.info("raw_root=%s processed_root=%s", settings.raw_root, settings.processed_root)

    app = create_app(settings)
    uvicorn.run(app, host=settings.host, port=settings.port, log_level="warning")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
