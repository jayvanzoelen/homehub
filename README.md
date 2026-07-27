# Home Hub

Fridge-mounted household hub for an old iPad: shared chores, pantry inventory
via the selfie camera, and a simple motion-aware security mode.

See [PRODUCT.md](./PRODUCT.md) for the full product constitution.

## Quick start

```bash
uv sync
uv run homehub
# or: pip install -e ".[dev]" && homehub
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

Full fridge-kiosk steps: [docs/IPAD_SETUP.md](./docs/IPAD_SETUP.md).

## Development

```bash
uv run pytest
uv run ruff check .
```

## Layout

```
├── PRODUCT.md          # product constitution
├── config.toml
├── pyproject.toml
├── src/homehub/        # FastAPI app
├── templates/          # Jinja2 pages
├── static/             # CSS, JS, PWA manifest
├── data/               # SQLite + media (gitignored)
└── tests/
```
