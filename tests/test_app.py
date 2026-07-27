"""Tests for Home Hub API and pages."""

from __future__ import annotations

import io
from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from sqlmodel import Session, SQLModel, create_engine, select

from homehub import db as dbmod
from homehub.app import create_app
from homehub.config import AppConfig, MediaConfig, get_config
from homehub.models import HubState, InventoryItem, Person, Task


@pytest.fixture()
def client(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> TestClient:
    get_config.cache_clear()
    db_path = tmp_path / "test.db"
    media = tmp_path / "media"
    (media / "inventory").mkdir(parents=True)
    (media / "security").mkdir(parents=True)

    engine = create_engine(f"sqlite:///{db_path}", connect_args={"check_same_thread": False})
    monkeypatch.setattr(dbmod, "engine", engine)
    monkeypatch.setattr(dbmod, "DB_PATH", db_path)
    monkeypatch.setattr(dbmod, "DATA_DIR", tmp_path)

    test_cfg = AppConfig(media=MediaConfig(root=str(media)))
    monkeypatch.setattr("homehub.app.get_config", lambda: test_cfg)
    monkeypatch.setattr("homehub.db.get_config", lambda: test_cfg)
    monkeypatch.setattr("homehub.vision.get_config", lambda: test_cfg)

    SQLModel.metadata.create_all(engine)
    with Session(engine) as session:
        session.add(HubState(armed=False))
        session.add(Person(name="Alex", color="#3d6b5a", initials="AL"))
        session.add(Person(name="Sam", color="#8b5a2b", initials="SA"))
        session.commit()

    app = create_app()
    with TestClient(app) as test_client:
        yield test_client
    get_config.cache_clear()


def test_home_page(client: TestClient) -> None:
    res = client.get("/")
    assert res.status_code == 200
    assert b"Hub" in res.content


def test_create_and_complete_task(client: TestClient) -> None:
    res = client.post(
        "/tasks",
        data={"title": "Trash night", "assignee_id": "", "cadence": "weekly"},
        follow_redirects=False,
    )
    assert res.status_code == 303

    with Session(dbmod.engine) as session:
        task = session.exec(select(Task)).first()
        assert task is not None
        task_id = task.id

    res = client.post(f"/tasks/{task_id}/complete", follow_redirects=False)
    assert res.status_code == 303
    with Session(dbmod.engine) as session:
        task = session.get(Task, task_id)
        assert task is not None
        assert task.done_at is not None


def test_scan_saves_inventory_item(client: TestClient) -> None:
    jpeg = bytes.fromhex(
        "ffd8ffe000104a46494600010100000100010000ffdb004300080606070605080707"
        "070909080a0c140d0c0b0b0c1912130f141d1a1f1e1d1a1c1c20242e2720222c231c"
        "1c2837292c30313434341f27393d38323c2e333432ffdb0043010909090c0b0c180d"
        "0d1832211c2132323232323232323232323232323232323232323232323232323232"
        "323232323232323232323232323232323232323232ffc00011080001000103011100"
        "0211031101ffc40014000100000000000000000000000000000008ffc40014100100"
        "00000000000000000000000000000000ffda000c0301000210031000003f00bf80ffd9"
    )
    res = client.post(
        "/api/scan",
        data={
            "name": "Oat milk",
            "quantity": "2",
            "unit": "carton",
            "location": "fridge",
            "suggest": "false",
        },
        files={"photo": ("capture.jpg", io.BytesIO(jpeg), "image/jpeg")},
    )
    assert res.status_code == 200
    body = res.json()
    assert body["ok"] is True
    assert body["name"] == "Oat milk"

    with Session(dbmod.engine) as session:
        item = session.exec(select(InventoryItem)).first()
        assert item is not None
        assert item.name == "Oat milk"
        assert item.quantity == 2


def test_security_arm_and_motion(client: TestClient) -> None:
    res = client.post("/api/security/arm", data={"armed": "true"})
    assert res.status_code == 200
    assert res.json()["armed"] is True

    jpeg = bytes.fromhex(
        "ffd8ffe000104a46494600010100000100010000ffdb004300080606070605080707"
        "070909080a0c140d0c0b0b0c1912130f141d1a1f1e1d1a1c1c20242e2720222c231c"
        "1c2837292c30313434341f27393d38323c2e333432ffdb0043010909090c0b0c180d"
        "0d1832211c2132323232323232323232323232323232323232323232323232323232"
        "323232323232323232323232323232323232323232ffc00011080001000103011100"
        "0211031101ffc40014000100000000000000000000000000000008ffc40014100100"
        "00000000000000000000000000000000ffda000c0301000210031000003f00bf80ffd9"
    )
    res = client.post(
        "/api/security/motion",
        data={"note": "test motion"},
        files={"photo": ("motion.jpg", io.BytesIO(jpeg), "image/jpeg")},
    )
    assert res.status_code == 200
    assert res.json()["ok"] is True


def test_motion_ignored_when_disarmed(client: TestClient) -> None:
    jpeg = bytes.fromhex(
        "ffd8ffe000104a46494600010100000100010000ffdb004300080606070605080707"
        "070909080a0c140d0c0b0b0c1912130f141d1a1f1e1d1a1c1c20242e2720222c231c"
        "1c2837292c30313434341f27393d38323c2e333432ffdb0043010909090c0b0c180d"
        "0d1832211c2132323232323232323232323232323232323232323232323232323232"
        "323232323232323232323232323232323232323232ffc00011080001000103011100"
        "0211031101ffc40014000100000000000000000000000000000008ffc40014100100"
        "00000000000000000000000000000000ffda000c0301000210031000003f00bf80ffd9"
    )
    res = client.post(
        "/api/security/motion",
        files={"photo": ("motion.jpg", io.BytesIO(jpeg), "image/jpeg")},
    )
    assert res.status_code == 200
    assert res.json()["ignored"] is True


def test_status_endpoint(client: TestClient) -> None:
    res = client.get("/api/status")
    assert res.status_code == 200
    assert "armed" in res.json()
