"""FastAPI application: Home Hub fridge kiosk."""

from __future__ import annotations

import shutil
import uuid
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from datetime import UTC, date, datetime
from pathlib import Path
from typing import Annotated
from urllib.parse import urlparse

from fastapi import Depends, FastAPI, File, Form, HTTPException, Query, Request, UploadFile
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from sqlmodel import Session, col, select

from homehub.config import ROOT, get_config
from homehub.db import get_session, init_db
from homehub.models import (
    HubState,
    InventoryItem,
    ItemLocation,
    Person,
    SecurityEvent,
    SecurityEventKind,
    Task,
    TaskCadence,
)
from homehub.vision import suggest_item_name

TEMPLATES = Jinja2Templates(directory=str(ROOT / "templates"))
STATIC_DIR = ROOT / "static"


def _utcnow() -> datetime:
    return datetime.now(UTC).replace(tzinfo=None)


def create_app() -> FastAPI:
    cfg = get_config()

    @asynccontextmanager
    async def lifespan(_app: FastAPI) -> AsyncIterator[None]:
        init_db()
        yield

    app = FastAPI(title="Home Hub", docs_url="/api/docs", redoc_url=None, lifespan=lifespan)
    app.mount("/static", StaticFiles(directory=str(STATIC_DIR)), name="static")
    media = cfg.media_path
    media.mkdir(parents=True, exist_ok=True)
    app.mount("/media", StaticFiles(directory=str(media)), name="media")
    def _hub_state(session: Session) -> HubState:
        state = session.exec(select(HubState)).first()
        if state is None:
            state = HubState(armed=False)
            session.add(state)
            session.commit()
            session.refresh(state)
        return state

    def _people(session: Session) -> list[Person]:
        return list(session.exec(select(Person).where(Person.active == True)).all())  # noqa: E712

    def _check_pin(pin: str | None) -> None:
        expected = get_config().household.pin
        if not expected:
            return
        if (pin or "") != expected:
            raise HTTPException(status_code=403, detail="Invalid PIN")

    @app.get("/", response_class=HTMLResponse)
    def home(
        request: Request,
        session: Annotated[Session, Depends(get_session)],
    ) -> HTMLResponse:
        state = _hub_state(session)
        people = _people(session)
        open_tasks = session.exec(
            select(Task).where(col(Task.done_at).is_(None)).order_by(Task.created_at)
        ).all()
        items = session.exec(
            select(InventoryItem).order_by(col(InventoryItem.updated_at).desc()).limit(8)
        ).all()
        events = session.exec(
            select(SecurityEvent).order_by(col(SecurityEvent.created_at).desc()).limit(5)
        ).all()
        active = next((p for p in people if p.id == state.active_person_id), None)
        return TEMPLATES.TemplateResponse(
            request,
            "home.html",
            {
                "cfg": get_config(),
                "state": state,
                "people": people,
                "active_person": active,
                "open_tasks": open_tasks,
                "recent_items": items,
                "recent_events": events,
                "tab": "home",
            },
        )

    @app.get("/tasks", response_class=HTMLResponse)
    def tasks_page(
        request: Request,
        session: Annotated[Session, Depends(get_session)],
        show: str = Query(default="open"),
    ) -> HTMLResponse:
        state = _hub_state(session)
        people = _people(session)
        query = select(Task).order_by(col(Task.created_at).desc())
        if show != "all":
            query = query.where(col(Task.done_at).is_(None))
        tasks = session.exec(query).all()
        by_id = {p.id: p for p in people}
        active = next((p for p in people if p.id == state.active_person_id), None)
        return TEMPLATES.TemplateResponse(
            request,
            "tasks.html",
            {
                "cfg": get_config(),
                "state": state,
                "people": people,
                "active_person": active,
                "tasks": tasks,
                "people_by_id": by_id,
                "show": show,
                "tab": "tasks",
            },
        )

    @app.post("/tasks")
    def create_task(
        session: Annotated[Session, Depends(get_session)],
        title: Annotated[str, Form()],
        assignee_id: Annotated[str, Form()] = "",
        cadence: Annotated[str, Form()] = "once",
        due_date: Annotated[str, Form()] = "",
    ) -> RedirectResponse:
        title = title.strip()
        if not title:
            raise HTTPException(status_code=400, detail="Title required")
        due: date | None = None
        if due_date.strip():
            due = date.fromisoformat(due_date.strip())
        assignee: int | None = int(assignee_id) if assignee_id.strip() else None
        task = Task(
            title=title,
            assignee_id=assignee,
            cadence=TaskCadence(cadence),
            due_date=due,
        )
        session.add(task)
        session.commit()
        return RedirectResponse(url="/tasks", status_code=303)

    @app.post("/tasks/{task_id}/complete")
    def complete_task(
        task_id: int,
        session: Annotated[Session, Depends(get_session)],
    ) -> RedirectResponse:
        task = session.get(Task, task_id)
        if task is None:
            raise HTTPException(status_code=404, detail="Task not found")
        state = _hub_state(session)
        task.done_at = _utcnow()
        task.done_by_id = state.active_person_id
        session.add(task)
        session.commit()
        return RedirectResponse(url="/tasks", status_code=303)

    @app.post("/tasks/{task_id}/reopen")
    def reopen_task(
        task_id: int,
        session: Annotated[Session, Depends(get_session)],
    ) -> RedirectResponse:
        task = session.get(Task, task_id)
        if task is None:
            raise HTTPException(status_code=404, detail="Task not found")
        task.done_at = None
        task.done_by_id = None
        session.add(task)
        session.commit()
        return RedirectResponse(url="/tasks?show=all", status_code=303)

    @app.get("/pantry", response_class=HTMLResponse)
    def pantry_page(
        request: Request,
        session: Annotated[Session, Depends(get_session)],
        location: str = Query(default="all"),
    ) -> HTMLResponse:
        state = _hub_state(session)
        people = _people(session)
        query = select(InventoryItem).order_by(col(InventoryItem.updated_at).desc())
        if location != "all":
            query = query.where(InventoryItem.location == ItemLocation(location))
        items = session.exec(query).all()
        active = next((p for p in people if p.id == state.active_person_id), None)
        return TEMPLATES.TemplateResponse(
            request,
            "pantry.html",
            {
                "cfg": get_config(),
                "state": state,
                "people": people,
                "active_person": active,
                "items": items,
                "location": location,
                "locations": list(ItemLocation),
                "tab": "pantry",
            },
        )

    @app.get("/scan", response_class=HTMLResponse)
    def scan_page(
        request: Request,
        session: Annotated[Session, Depends(get_session)],
    ) -> HTMLResponse:
        state = _hub_state(session)
        people = _people(session)
        active = next((p for p in people if p.id == state.active_person_id), None)
        return TEMPLATES.TemplateResponse(
            request,
            "scan.html",
            {
                "cfg": get_config(),
                "state": state,
                "people": people,
                "active_person": active,
                "locations": list(ItemLocation),
                "vision_enabled": get_config().vision.enabled,
                "tab": "scan",
            },
        )

    @app.post("/api/scan")
    async def api_scan(
        session: Annotated[Session, Depends(get_session)],
        photo: UploadFile = File(...),
        name: Annotated[str, Form()] = "",
        quantity: Annotated[float, Form()] = 1.0,
        unit: Annotated[str, Form()] = "ea",
        location: Annotated[str, Form()] = "pantry",
        expires_on: Annotated[str | None, Form()] = None,
        suggest: Annotated[str, Form()] = "false",
    ) -> dict:
        state = _hub_state(session)
        suffix = Path(photo.filename or "capture.jpg").suffix.lower() or ".jpg"
        if suffix not in {".jpg", ".jpeg", ".png", ".webp"}:
            suffix = ".jpg"
        filename = f"{_utcnow().strftime('%Y%m%dT%H%M%S')}_{uuid.uuid4().hex[:8]}{suffix}"
        dest = get_config().media_path / "inventory" / filename
        with dest.open("wb") as out:
            shutil.copyfileobj(photo.file, out)

        want_suggest = suggest.strip().lower() in {"1", "true", "yes", "on"}
        suggested: str | None = None
        if want_suggest or not name.strip():
            suggested = await suggest_item_name(dest)

        final_name = name.strip() or (suggested or "")
        if not final_name:
            # Keep the photo for a follow-up name confirmation in the UI.
            return {
                "ok": False,
                "needs_name": True,
                "suggested_name": suggested,
                "photo_path": f"inventory/{filename}",
            }

        expires: date | None = None
        if expires_on:
            expires = date.fromisoformat(expires_on)

        item = InventoryItem(
            name=final_name,
            quantity=quantity,
            unit=unit.strip() or "ea",
            location=ItemLocation(location),
            expires_on=expires,
            photo_path=f"inventory/{filename}",
            added_by_id=state.active_person_id,
            updated_at=_utcnow(),
        )
        session.add(item)
        session.commit()
        session.refresh(item)
        return {
            "ok": True,
            "item_id": item.id,
            "name": item.name,
            "suggested_name": suggested,
            "photo_path": item.photo_path,
        }

    @app.post("/api/scan/confirm")
    def api_scan_confirm(
        session: Annotated[Session, Depends(get_session)],
        name: Annotated[str, Form()],
        photo_path: Annotated[str, Form()],
        quantity: Annotated[float, Form()] = 1.0,
        unit: Annotated[str, Form()] = "ea",
        location: Annotated[str, Form()] = "pantry",
        expires_on: Annotated[str | None, Form()] = None,
    ) -> dict:
        state = _hub_state(session)
        name = name.strip()
        if not name:
            raise HTTPException(status_code=400, detail="Name required")
        # Prevent path traversal — only allow inventory/ filenames we wrote.
        safe = Path(photo_path)
        if safe.parts[0] != "inventory" or len(safe.parts) != 2:
            raise HTTPException(status_code=400, detail="Invalid photo path")
        full = get_config().media_path / safe
        if not full.exists():
            raise HTTPException(status_code=404, detail="Photo not found")

        expires: date | None = None
        if expires_on:
            expires = date.fromisoformat(expires_on)
        item = InventoryItem(
            name=name,
            quantity=quantity,
            unit=unit.strip() or "ea",
            location=ItemLocation(location),
            expires_on=expires,
            photo_path=str(safe).replace("\\", "/"),
            added_by_id=state.active_person_id,
            updated_at=_utcnow(),
        )
        session.add(item)
        session.commit()
        session.refresh(item)
        return {"ok": True, "item_id": item.id, "name": item.name}

    @app.post("/pantry/{item_id}/adjust")
    def adjust_item(
        item_id: int,
        session: Annotated[Session, Depends(get_session)],
        delta: Annotated[float, Form()],
    ) -> RedirectResponse:
        item = session.get(InventoryItem, item_id)
        if item is None:
            raise HTTPException(status_code=404, detail="Item not found")
        item.quantity = max(0.0, item.quantity + delta)
        item.updated_at = _utcnow()
        session.add(item)
        session.commit()
        return RedirectResponse(url="/pantry", status_code=303)

    @app.post("/pantry/{item_id}/delete")
    def delete_item(
        item_id: int,
        session: Annotated[Session, Depends(get_session)],
    ) -> RedirectResponse:
        item = session.get(InventoryItem, item_id)
        if item is None:
            raise HTTPException(status_code=404, detail="Item not found")
        session.delete(item)
        session.commit()
        return RedirectResponse(url="/pantry", status_code=303)

    @app.get("/security", response_class=HTMLResponse)
    def security_page(
        request: Request,
        session: Annotated[Session, Depends(get_session)],
    ) -> HTMLResponse:
        state = _hub_state(session)
        people = _people(session)
        events = session.exec(
            select(SecurityEvent).order_by(col(SecurityEvent.created_at).desc()).limit(40)
        ).all()
        active = next((p for p in people if p.id == state.active_person_id), None)
        return TEMPLATES.TemplateResponse(
            request,
            "security.html",
            {
                "cfg": get_config(),
                "state": state,
                "people": people,
                "active_person": active,
                "events": events,
                "tab": "security",
            },
        )

    @app.post("/api/security/arm")
    def arm(
        session: Annotated[Session, Depends(get_session)],
        pin: Annotated[str, Form()] = "",
        armed: Annotated[str, Form()] = "true",
    ) -> dict:
        _check_pin(pin or None)
        is_armed = armed.strip().lower() in {"1", "true", "yes", "on"}
        state = _hub_state(session)
        state.armed = is_armed
        session.add(state)
        event = SecurityEvent(
            kind=SecurityEventKind.ARMED if is_armed else SecurityEventKind.DISARMED,
            note="Armed from hub" if is_armed else "Disarmed from hub",
        )
        session.add(event)
        session.commit()
        return {"ok": True, "armed": state.armed}

    @app.post("/api/security/motion")
    async def motion_event(
        session: Annotated[Session, Depends(get_session)],
        photo: UploadFile = File(...),
        note: Annotated[str, Form()] = "Motion detected",
    ) -> dict:
        state = _hub_state(session)
        if not state.armed:
            return {"ok": False, "ignored": True, "reason": "not_armed"}

        cfg = get_config()
        # Enforce retention / cooldown roughly on the server.
        latest = session.exec(
            select(SecurityEvent)
            .where(SecurityEvent.kind == SecurityEventKind.MOTION)
            .order_by(col(SecurityEvent.created_at).desc())
        ).first()
        cooldown = cfg.security.cooldown_seconds
        if latest and (_utcnow() - latest.created_at).total_seconds() < cooldown:
            return {"ok": False, "ignored": True, "reason": "cooldown"}

        suffix = Path(photo.filename or "motion.jpg").suffix.lower() or ".jpg"
        if suffix not in {".jpg", ".jpeg", ".png", ".webp"}:
            suffix = ".jpg"
        filename = f"{_utcnow().strftime('%Y%m%dT%H%M%S')}_{uuid.uuid4().hex[:8]}{suffix}"
        dest = cfg.media_path / "security" / filename
        with dest.open("wb") as out:
            shutil.copyfileobj(photo.file, out)

        event = SecurityEvent(
            kind=SecurityEventKind.MOTION,
            snapshot_path=f"security/{filename}",
            note=note[:240],
        )
        session.add(event)
        session.commit()
        session.refresh(event)

        # Trim old motion events.
        motion_events = session.exec(
            select(SecurityEvent)
            .where(SecurityEvent.kind == SecurityEventKind.MOTION)
            .order_by(col(SecurityEvent.created_at).desc())
        ).all()
        for stale in motion_events[cfg.security.max_events :]:
            if stale.snapshot_path:
                path = cfg.media_path / stale.snapshot_path
                if path.exists():
                    path.unlink()
            session.delete(stale)
        session.commit()

        return {"ok": True, "event_id": event.id, "snapshot_path": event.snapshot_path}

    @app.get("/api/status")
    def status(session: Annotated[Session, Depends(get_session)]) -> dict:
        state = _hub_state(session)
        return {
            "household": get_config().household.name,
            "armed": state.armed,
            "active_person_id": state.active_person_id,
            "vision_enabled": get_config().vision.enabled,
            "motion_threshold": get_config().security.motion_threshold,
            "cooldown_seconds": get_config().security.cooldown_seconds,
        }

    @app.post("/api/active-person")
    def set_active_person(
        request: Request,
        session: Annotated[Session, Depends(get_session)],
        person_id: Annotated[int, Form()],
    ) -> RedirectResponse:
        person = session.get(Person, person_id)
        if person is None or not person.active:
            raise HTTPException(status_code=404, detail="Person not found")
        state = _hub_state(session)
        state.active_person_id = person.id
        session.add(state)
        session.commit()
        referer = request.headers.get("referer") or "/"
        # Only allow local redirects.
        if not referer.startswith("/") and "://" in referer:
            path = urlparse(referer).path or "/"
            referer = path
        return RedirectResponse(url=referer, status_code=303)

    @app.post("/people")
    def add_person(
        session: Annotated[Session, Depends(get_session)],
        name: Annotated[str, Form()],
        color: Annotated[str, Form()] = "#3d6b5a",
    ) -> RedirectResponse:
        name = name.strip()
        if not name:
            raise HTTPException(status_code=400, detail="Name required")
        initials = ("".join(part[0] for part in name.split()[:2]) or name[:2]).upper()
        session.add(Person(name=name, color=color, initials=initials[:3]))
        session.commit()
        return RedirectResponse(url="/", status_code=303)

    return app


app = create_app()


def main() -> None:
    import uvicorn

    cfg = get_config()
    uvicorn.run(
        "homehub.app:app",
        host=cfg.server.host,
        port=cfg.server.port,
        reload=False,
    )


if __name__ == "__main__":
    main()
