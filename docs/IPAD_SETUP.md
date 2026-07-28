# iPad fridge-kiosk setup

## Recommended: native client

The native client is recommended for a Home Hub served over ordinary HTTP
because iPad browsers allow camera access only from a trusted HTTPS origin.

1. Run the hub on a machine that stays on your Wi-Fi:
   `uv sync && uv run homehub`
2. Verify `http://<that-machine-lan-ip>:8787` opens from the iPad.
3. Install the Xcode project from `ios/HomeHub/HomeHub.xcodeproj` by following
   [`ios/README.md`](../ios/README.md).
4. Enter the server address and allow Local Network and Camera access.
5. Settings → Accessibility → Guided Access → On. Triple-click the Home button
   to lock into Home Hub.
6. Mount the iPad with the **screen facing the kitchen** so the front camera sees
   the room.

The app keeps the screen awake while foregrounded. Guard must remain open to
detect motion and disarms when you leave it; iPadOS suspends camera capture in
the background.

## PWA alternative

For Home, Board, and Pantry only:

1. Open `http://<that-machine-lan-ip>:8787` in Safari.
2. Share → Add to Home Screen.
3. Open the Home Hub icon and enable Guided Access.

Scan and Guard require the server to use trusted HTTPS when running as a PWA.

Optional PIN: set `[household] pin` in `config.toml` before arming Guard.
Optional vision labels: set `ANTHROPIC_API_KEY` and `[vision] enabled = true`.
