import os

os.environ.setdefault("ADMIN_BCRYPT_ROUNDS", "4")

import pytest

from services import db as dbmod


@pytest.fixture(autouse=True)
def _tmp_db(tmp_path, monkeypatch):
    monkeypatch.setattr(dbmod, "DB_PATH", str(tmp_path / "t.db"))
