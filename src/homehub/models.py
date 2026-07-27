"""SQLModel tables for Home Hub."""

from __future__ import annotations

from datetime import UTC, date, datetime
from enum import StrEnum

from sqlmodel import Field, SQLModel


def _utcnow() -> datetime:
    return datetime.now(UTC).replace(tzinfo=None)


class TaskCadence(StrEnum):
    ONCE = "once"
    DAILY = "daily"
    WEEKLY = "weekly"


class ItemLocation(StrEnum):
    FRIDGE = "fridge"
    PANTRY = "pantry"
    FREEZER = "freezer"
    OTHER = "other"


class SecurityEventKind(StrEnum):
    MOTION = "motion"
    ARMED = "armed"
    DISARMED = "disarmed"


class Person(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    name: str = Field(index=True, max_length=64)
    color: str = Field(default="#3d6b5a", max_length=16)
    initials: str = Field(default="?", max_length=3)
    active: bool = Field(default=True)


class Task(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    title: str = Field(max_length=200)
    assignee_id: int | None = Field(default=None, foreign_key="person.id", index=True)
    cadence: TaskCadence = Field(default=TaskCadence.ONCE)
    due_date: date | None = Field(default=None, index=True)
    done_at: datetime | None = Field(default=None, index=True)
    done_by_id: int | None = Field(default=None, foreign_key="person.id")
    created_at: datetime = Field(default_factory=_utcnow)


class InventoryItem(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    name: str = Field(index=True, max_length=120)
    quantity: float = Field(default=1.0)
    unit: str = Field(default="ea", max_length=24)
    location: ItemLocation = Field(default=ItemLocation.PANTRY)
    expires_on: date | None = Field(default=None)
    photo_path: str | None = Field(default=None, max_length=512)
    added_by_id: int | None = Field(default=None, foreign_key="person.id")
    created_at: datetime = Field(default_factory=_utcnow)
    updated_at: datetime = Field(default_factory=_utcnow)


class SecurityEvent(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    kind: SecurityEventKind = Field(index=True)
    created_at: datetime = Field(default_factory=_utcnow, index=True)
    snapshot_path: str | None = Field(default=None, max_length=512)
    note: str | None = Field(default=None, max_length=240)


class HubState(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    armed: bool = Field(default=False)
    active_person_id: int | None = Field(default=None, foreign_key="person.id")
