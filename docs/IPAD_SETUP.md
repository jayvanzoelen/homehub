# iPad fridge-kiosk setup

1. Run the hub on a machine that stays on your Wi‑Fi:
   `cd homehub && uv sync && uv run homehub`
2. On the iPad, open Safari to `http://<that-machine-lan-ip>:8787`.
3. Share → Add to Home Screen.
4. Open the Home Hub icon (standalone). Allow camera when prompted.
5. Settings → Display & Brightness → Auto-Lock → Never (while plugged in).
6. Settings → Accessibility → Guided Access → On. Triple-click Home/Power to lock into the hub.
7. Mount on the fridge with the **screen facing the kitchen** so the selfie camera sees the room.

Optional PIN: set `[household] pin` in `config.toml` before arming Guard.
Optional vision labels: set `ANTHROPIC_API_KEY` and `[vision] enabled = true`.
