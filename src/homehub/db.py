"""Database engine and session helpers."""

from __future__ import annotations

from collections.abc import Iterator

from sqlalchemy.engine import Engine
from sqlmodel import Session, SQLModel, create_engine, select

from homehub.config import ROOT, get_config
from homehub.models import HubState, Person

DATA_DIR = ROOT / "data"
DB_PATH = DATA_DIR / "homehub.db"


def _ensure_dirs() -> None:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    get_config().media_path.mkdir(parents=True, exist_ok=True)
    (get_config().media_path / "inventory").mkdir(parents=True, exist_ok=True)
    (get_config().media_path / "security").mkdir(parents=True, exist_ok=True)


def get_engine() -> Engine:
    _ensure_dirs()
    return create_engine(
        f"sqlite:///{DB_PATH}",
        connect_args={"check_same_thread": False},
    )


engine = get_engine()


def init_db() -> None:
    SQLModel.metadata.create_all(engine)
    with Session(engine) as session:
        if session.exec(select(HubState)).first() is None:
            session.add(HubState(armed=False))
            session.commit()
        if session.exec(select(Person)).first() is None:
            seed = [
                Person(name="Alex", color="#3d6b5a", initials="AL"),
                Person(name="Sam", color="#8b5a2b", initials="SA"),
                Person(name="Jordan", color="#2b4c7e", initials="JO"),
            ]
            session.add_all(seed)
            session.commit()


def get_session() -> Iterator[Session]:
    with Session(engine) as session:
        yield session
