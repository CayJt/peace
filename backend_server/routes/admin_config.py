import os
import time

import httpx
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from services import verse_provider
from services.admin_security import Admin, require_permission
from services.db import db, iso, now

router = APIRouter(prefix="/api/v1/admin/config")

PROVIDERS = ("quran.com", "kemenag")
# Only Quran.com has a server-side adapter today (services/verse_provider.py).
ADAPTERS = {"quran.com": True, "kemenag": False}
# Health-check targets are configurable; the Kemenag default is unverified.
HEALTH_URLS = {
    "quran.com": os.environ.get("QURAN_COM_HEALTH_URL", "https://api.quran.com/api/v4/chapters/1"),
    "kemenag": os.environ.get("KEMENAG_HEALTH_URL", "https://web-api.qurankemenag.net/quran-surah"),
}


class ProviderIn(BaseModel):
    provider: str


def get_provider(con) -> tuple[str, int | None, float | None]:
    r = con.execute("SELECT value, updated_by, updated_at FROM system_configs WHERE key='quran_data_provider'").fetchone()
    return (r["value"], r["updated_by"], r["updated_at"]) if r else ("quran.com", None, None)


def _state(con) -> dict:
    value, by, at = get_provider(con)
    return {
        "provider": value, "available": list(PROVIDERS), "adapter_implemented": ADAPTERS,
        "updated_by": by, "updated_at": iso(at),
    }


@router.get("/quran-provider")
def read_provider(_: Admin = Depends(require_permission("config.manage"))):
    with db() as con:
        return _state(con)


@router.put("/quran-provider")
def set_provider(body: ProviderIn, admin: Admin = Depends(require_permission("config.manage"))):
    if body.provider not in PROVIDERS:
        raise HTTPException(422, f"provider must be one of {', '.join(PROVIDERS)}")
    with db() as con:
        con.execute(
            "INSERT INTO system_configs(key,value,updated_by,updated_at) VALUES('quran_data_provider',?,?,?) "
            "ON CONFLICT(key) DO UPDATE SET value=excluded.value, updated_by=excluded.updated_by, updated_at=excluded.updated_at",
            (body.provider, admin.id, now()),
        )
        return _state(con)


@router.get("/quran-provider/health")
def provider_health(_: Admin = Depends(require_permission("config.manage"))):
    out = {}
    for name, url in HEALTH_URLS.items():
        t0 = time.perf_counter()
        try:
            r = httpx.get(url, timeout=5, follow_redirects=True)
            out[name] = {"ok": r.status_code < 400, "status_code": r.status_code,
                         "latency_ms": round((time.perf_counter() - t0) * 1000), "error": None}
        except httpx.HTTPError as e:
            out[name] = {"ok": False, "status_code": None, "latency_ms": None, "error": type(e).__name__}
    return {"checked_at": iso(now()), "providers": out}


@router.post("/cache/clear")
def clear_cache(_: Admin = Depends(require_permission("config.manage"))):
    n = verse_provider.get_verse_provider().clear_cache()
    return {"cleared_entries": n}
