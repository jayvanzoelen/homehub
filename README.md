# Home Hub

Fridge-mounted household hub for an old iPad: shared chores, pantry inventory
via the selfie camera, and a simple motion-aware security mode.

See [PRODUCT.md](./PRODUCT.md) for the full product constitution.

> **Note:** This project was bootstrapped inside the Terrarium workspace because
> that was the only attached repo. It is a standalone app under `homehub/` and
> should be moved to its own repository before merging anything into Terrarium.

## Quick start

```bash
cd homehub
uv sync
uv run homehub
```

Open `http://<lan-ip>:8787` on the iPad Safari → Share → **Add to Home Screen**.
Enable **Guided Access** (Settings → Accessibility) so taps can’t escape the kiosk.

## What you get in v1

| Tab | Purpose |
|-----|---------|
| Board | Housemate tasks — claim, complete, add |
| Pantry | Inventory list with quantity / location |
| Scan | Selfie-camera capture → name the item → save |
| Security | Arm/disarm, live preview, motion stills |

Optional: set `ANTHROPIC_API_KEY` and enable vision in `config.toml` to auto-suggest
item names from the scan photo. Manual naming always works.

## Old iPad tips

- Use the **front camera** (faces the kitchen when fridge-mounted).
- Settings → Display & Brightness → Auto-Lock → **Never** while Guided Access is on (and plugged in).
- Dim the screen at night via iOS Night Shift / brightness; the hub has a calm idle clock.
- iOS 12+ is enough for camera + basic PWA install.

## Development

```bash
cd homehub
uv run pytest
uv run ruff check .
```

## Layout

```
homehub/
├── PRODUCT.md          # product constitution
├── config.toml
├── pyproject.toml
├── src/homehub/        # FastAPI app
├── templates/          # Jinja2 pages
├── static/             # CSS, JS, PWA manifest
├── data/               # SQLite + media (gitignored)
└── tests/
```
