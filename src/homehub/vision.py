"""Optional vision labeling for inventory scans."""

from __future__ import annotations

import base64
import os
from pathlib import Path

import httpx

from homehub.config import get_config


async def suggest_item_name(image_path: Path) -> str | None:
    """Return a short grocery-style name, or None if vision is unavailable."""
    cfg = get_config()
    api_key = os.environ.get("ANTHROPIC_API_KEY", "").strip()
    if not cfg.vision.enabled or not api_key:
        return None
    if not image_path.exists():
        return None

    media_type = "image/jpeg"
    suffix = image_path.suffix.lower()
    if suffix == ".png":
        media_type = "image/png"
    elif suffix == ".webp":
        media_type = "image/webp"

    data = base64.standard_b64encode(image_path.read_bytes()).decode("ascii")
    payload = {
        "model": cfg.vision.model,
        "max_tokens": 64,
        "messages": [
            {
                "role": "user",
                "content": [
                    {
                        "type": "image",
                        "source": {
                            "type": "base64",
                            "media_type": media_type,
                            "data": data,
                        },
                    },
                    {
                        "type": "text",
                        "text": (
                            "Identify the main grocery or household item in this photo. "
                            "Reply with ONLY a short name (2–4 words), no punctuation."
                        ),
                    },
                ],
            }
        ],
    }
    headers = {
        "x-api-key": api_key,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json",
    }
    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            response = await client.post(
                "https://api.anthropic.com/v1/messages",
                headers=headers,
                json=payload,
            )
            response.raise_for_status()
            body = response.json()
    except (httpx.HTTPError, ValueError, KeyError):
        return None

    parts = body.get("content") or []
    texts = [p.get("text", "").strip() for p in parts if p.get("type") == "text"]
    if not texts:
        return None
    name = texts[0].splitlines()[0].strip().strip('"').strip("'")
    return name[:120] if name else None
