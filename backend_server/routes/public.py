"""Endpoints used by the mobile app (not admin)."""
import time

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, Field

from routes.admin_config import get_provider
from routes.auth import current_user, optional_user
from services.db import db, now

router = APIRouter(prefix="/api/v1")

_feedback_hits: dict[str, list[float]] = {}
FEEDBACK_PER_HOUR = 5


class FeedbackIn(BaseModel):
    category: str = "other"
    message: str = Field(min_length=3, max_length=2000)
    app_version: str = Field(default="", max_length=32)


@router.post("/feedback", status_code=201)
def send_feedback(body: FeedbackIn, request: Request, user=Depends(optional_user)):
    if body.category not in ("bug", "suggestion", "content", "other"):
        raise HTTPException(422, "category must be bug, suggestion, content or other")
    ip = request.client.host if request.client else "?"
    hits = [t for t in _feedback_hits.get(ip, []) if time.time() - t < 3600]
    if len(hits) >= FEEDBACK_PER_HOUR:
        raise HTTPException(429, "too many submissions, try again later")
    _feedback_hits[ip] = hits + [time.time()]
    t = now()
    with db() as con:
        cur = con.execute(
            "INSERT INTO user_feedbacks(user_id,category,message,app_version,status,admin_notes,created_at,updated_at) "
            "VALUES(?,?,?,?,'open','',?,?)",
            (str(user["id"]) if user else "anonymous", body.category, body.message.strip(), body.app_version, t, t),
        )
    return {"id": cur.lastrowid, "status": "open"}


@router.post("/heartbeat", status_code=204)
def heartbeat(user=Depends(current_user)):
    with db() as con:
        con.execute(
            "INSERT INTO user_heartbeats(user_id,last_seen) VALUES(?,?) "
            "ON CONFLICT(user_id) DO UPDATE SET last_seen=excluded.last_seen",
            (user["id"], now()),
        )


class SessionIn(BaseModel):
    page: int = Field(ge=1, le=604)
    duration_sec: int = Field(ge=0, le=6 * 3600)
    letters_evaluated: int = Field(ge=0, le=100_000)
    score: float = Field(ge=0, le=1)
    khatam_count: int = Field(default=0, ge=0, le=10_000)


@router.post("/murajaah/sessions", status_code=201)
def upload_session(body: SessionIn, user=Depends(current_user)):
    with db() as con:
        cur = con.execute(
            "INSERT INTO murajaah_sessions(user_id,page,duration_sec,letters_evaluated,score,khatam_count,created_at) "
            "VALUES(?,?,?,?,?,?,?)",
            (user["id"], body.page, body.duration_sec, body.letters_evaluated, body.score, body.khatam_count, now()),
        )
    return {"id": cur.lastrowid}


@router.get("/config/public")
def public_config():
    with db() as con:
        provider, _, _ = get_provider(con)
    return {"quran_data_provider": provider}
