"""Home Hub configuration loaded from config.toml."""

from __future__ import annotations

import tomllib
from functools import lru_cache
from pathlib import Path
from typing import Any

from pydantic import BaseModel, Field

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CONFIG_PATH = ROOT / "config.toml"


class ServerConfig(BaseModel):
    host: str = "0.0.0.0"
    port: int = 8787


class HouseholdConfig(BaseModel):
    name: str = "Home"
    pin: str = ""


class VisionConfig(BaseModel):
    enabled: bool = False
    model: str = "claude-haiku-4-5"


class SecurityConfig(BaseModel):
    motion_threshold: int = 28
    cooldown_seconds: int = 8
    max_events: int = 200


class MediaConfig(BaseModel):
    root: str = "data/media"


class AppConfig(BaseModel):
    server: ServerConfig = Field(default_factory=ServerConfig)
    household: HouseholdConfig = Field(default_factory=HouseholdConfig)
    vision: VisionConfig = Field(default_factory=VisionConfig)
    security: SecurityConfig = Field(default_factory=SecurityConfig)
    media: MediaConfig = Field(default_factory=MediaConfig)

    @property
    def media_path(self) -> Path:
        path = Path(self.media.root)
        if not path.is_absolute():
            path = ROOT / path
        return path


def _load_toml(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    with path.open("rb") as fh:
        return tomllib.load(fh)


@lru_cache(maxsize=1)
def get_config(path: str | None = None) -> AppConfig:
    config_path = Path(path) if path else DEFAULT_CONFIG_PATH
    return AppConfig.model_validate(_load_toml(config_path))
