# Home Hub — Product Constitution

Fridge-mounted home hub for an old iPad. Shared household OS: chores, pantry,
and a simple security eye. Local-first. Touch-first. Readable from across the kitchen.

## Goals

1. **Chore board** — see who owes what, tap to mark done, fair enough to settle arguments.
2. **Inventory by camera** — hold an item up to the selfie camera, confirm, it’s in the pantry list.
3. **Security mode** — when nobody’s home, the front camera watches the room and alerts on motion.

## Non-goals (v1)

- Not a full smart-home controller (no Matter/Zigbee/HomeKit bridge yet).
- Not a cloud SaaS. Runs on your LAN. Optional LLM vision calls only.
- Not a standalone offline app. Both clients use the local Home Hub server as
  the source of truth.
- Not multi-home / multi-tenancy.

## Why two iPad clients

- Old iPads often cap at iOS 12–15; modern native apps won’t install.
- Front (selfie) camera faces the kitchen when the iPad is fridge-mounted — correct for both scanning groceries and watching the room.
- “Add to Home Screen” + Guided Access = always-on kiosk without an Apple Developer account.
- One LAN URL works for phones too (add items from the shop).
- A native iPadOS 15 client supports the 6th-generation iPad and provides camera
  access when the local server uses HTTP; WebKit camera APIs require trusted
  HTTPS.

## Hardware assumptions

- iPad on a fridge mount, screen facing the kitchen, powered (or frequently charged).
- Selfie camera has a clear view of the room for security mode.
- A always-on host on the LAN (Pi, NAS, old laptop, or the Mac that runs other home services) serves the app.
- Housemates’ phones can open the same URL on Wi‑Fi.

## Product principles

- **Big targets.** Kitchen hands, arms-length viewing. Minimum ~56px tap areas.
- **Identity is a tap, not a login.** Pick your face/name on the hub; phones can use a light PIN later if needed.
- **Mechanism over nagging.** Track completion and inventory; don’t gamify or shame.
- **Privacy default.** Media stays on the LAN. Security clips are local. No analytics.
- **Degrade gracefully.** Vision labeling is assistive; manual entry always works offline-ish (LAN still required for sync).

## Personas

| Person | Job on the hub |
|--------|----------------|
| Housemate | Check off chores, add milk, peek who’s home |
| “On duty” cook | Scan groceries in, see what’s low |
| Away mode | Arm security before leaving |

## Information architecture

```
┌─────────────────────────────────────────────┐
│  HOME HUB          12:41   [Alex ▾]  🔒 Away │
├──────────┬──────────┬──────────┬────────────┤
│  Board   │  Pantry  │  Scan    │  Security  │
└──────────┴──────────┴──────────┴────────────┘
```

- **Board** — today’s open tasks, grouped by person or by due-soon.
- **Pantry** — inventory list, filters (low / expiring / all).
- **Scan** — full-screen camera capture → suggest label → confirm qty.
- **Security** — arm/disarm, live preview, recent motion events.

## Data model (v1)

- `Person` — id, name, color, avatar emoji/initials
- `Task` — title, assignee, cadence (once / daily / weekly), due, done_at, done_by
- `InventoryItem` — name, quantity, unit, location (fridge/pantry/freezer), expires_on, photo_path, added_by
- `SecurityEvent` — timestamp, kind (motion|armed|disarmed), snapshot_path, note
- `HubState` — armed bool, active_person_id

## Tech stack (fixed for v1)

- **Backend**: Python 3.11+, FastAPI, SQLite via SQLModel
- **UI**: server-rendered HTML + HTMX + small vanilla JS (old Safari friendly)
- **PWA**: web manifest + service worker for installability / light offline shell
- **Native iPad**: SwiftUI + WKWebView + AVFoundation, targeting iPadOS 15–17
- **Vision** (optional): Anthropic vision when `ANTHROPIC_API_KEY` is set; else manual label
- **Motion**: client-side frame diff on the iPad; POST snapshot on trigger
- **Package manager**: `uv`
- **Config**: `config.toml`

## Security & privacy

- Bind to LAN by default (`0.0.0.0` only if you know your network).
- Optional shared household PIN to arm/disarm and to leave kiosk.
- Snapshots stored under `data/media/`; never uploaded unless you add a notifier later.
- No third-party trackers in the UI.

## Success criteria for v1

- iPad can run as a Home Screen web app and survive a Safari refresh.
- Native client can connect to the LAN server and use Scan and Guard over HTTP.
- Three housemates can claim and complete tasks without accounts.
- An item can be added via selfie camera in under ~15 seconds (with manual name OK).
- Arming security and walking in front of the camera creates a visible event with a still.

## Roadmap (after v1)

1. Push/Telegram/email alerts on motion
2. Barcode fallback for packaged goods
3. Recurring task fairness (“who did trash last?”)
4. Low-stock shopping list shared to phones
5. Face-or-PIN person switching that’s harder to spoof
