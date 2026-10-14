import json

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field

from services.admin_security import Admin, require_permission
from services.db import db, iso, now

router = APIRouter(prefix="/api/v1/admin")
STATUSES = ("open", "in_progress", "resolved", "discarded")
CATEGORIES = ("bug", "suggestion", "content", "other")


@router.get("/chats/history")
def chat_history(
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    guardrail_only: bool = False,
    q: str | None = Query(None, max_length=100),
    _: Admin = Depends(require_permission("chats.view")),
):
    where, args = ["1=1"], []
    if guardrail_only:
        where.append("is_guardrail_triggered = 1")
    if q:
        like = "%" + q.replace("%", r"\%").replace("_", r"\_") + "%"
        where.append("(question LIKE ? ESCAPE '\\' OR answer LIKE ? ESCAPE '\\')")
        args += [like, like]
    with db() as con:
        total = con.execute(f"SELECT COUNT(*) c FROM chat_logs WHERE {' AND '.join(where)}", args).fetchone()["c"]
        rows = con.execute(
            f"SELECT * FROM chat_logs WHERE {' AND '.join(where)} ORDER BY id DESC LIMIT ? OFFSET ?",
            [*args, limit, offset],
        ).fetchall()
        blocked = con.execute("SELECT COUNT(*) c FROM chat_logs WHERE is_guardrail_triggered=1").fetchone()["c"]
        all_ = con.execute("SELECT COUNT(*) c FROM chat_logs").fetchone()["c"]
    return {
        "total": total, "guardrail_total": blocked, "all_total": all_,
        "items": [
            {
                "id": r["id"], "user_id": r["user_id"], "question": r["question"], "answer": r["answer"],
                "referenced_verses": json.loads(r["referenced_verses"] or "[]"),
                "is_guardrail_triggered": bool(r["is_guardrail_triggered"]), "created_at": iso(r["created_at"]),
            }
            for r in rows
        ],
    }


@router.get("/murajaah/sessions")
def murajaah_sessions(
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    _: Admin = Depends(require_permission("murajaah.view")),
):
    """Session summaries only: audio is streamed for scoring and never stored."""
    with db() as con:
        total = con.execute("SELECT COUNT(*) c FROM murajaah_sessions").fetchone()["c"]
        rows = con.execute(
            "SELECT m.*, u.full_name FROM murajaah_sessions m LEFT JOIN users u ON u.id=m.user_id "
            "ORDER BY m.id DESC LIMIT ? OFFSET ?", (limit, offset),
        ).fetchall()
    return {
        "total": total,
        "items": [
            {
                "id": r["id"], "user_id": r["user_id"], "name": r["full_name"] or "—", "page": r["page"],
                "duration_sec": r["duration_sec"], "letters_evaluated": r["letters_evaluated"],
                "score": r["score"], "created_at": iso(r["created_at"]),
            }
            for r in rows
        ],
    }


def _fb(r) -> dict:
    return {
        "id": r["id"], "user_id": r["user_id"], "category": r["category"], "message": r["message"],
        "app_version": r["app_version"], "status": r["status"], "admin_notes": r["admin_notes"],
        "created_at": iso(r["created_at"]), "updated_at": iso(r["updated_at"]),
    }


@router.get("/feedback")
def list_feedback(
    status: str | None = Query(None),
    category: str | None = Query(None),
    limit: int = Query(100, ge=1, le=300),
    offset: int = Query(0, ge=0),
    _: Admin = Depends(require_permission("feedback.manage")),
):
    if status and status not in STATUSES:
        raise HTTPException(422, f"status must be one of {', '.join(STATUSES)}")
    if category and category not in CATEGORIES:
        raise HTTPException(422, f"category must be one of {', '.join(CATEGORIES)}")
    where, args = ["1=1"], []
    for col, val in (("status", status), ("category", category)):
        if val:
            where.append(f"{col}=?")
            args.append(val)
    with db() as con:
        rows = con.execute(
            f"SELECT * FROM user_feedbacks WHERE {' AND '.join(where)} ORDER BY id DESC LIMIT ? OFFSET ?",
            [*args, limit, offset],
        ).fetchall()
        counts = {s: 0 for s in STATUSES}
        for r in con.execute("SELECT status, COUNT(*) c FROM user_feedbacks GROUP BY status"):
            counts[r["status"]] = r["c"]
    return {"counts": counts, "items": [_fb(r) for r in rows]}


class FeedbackPatch(BaseModel):
    status: str | None = None
    admin_notes: str | None = Field(default=None, max_length=2000)


@router.patch("/feedback/{feedback_id}")
def patch_feedback(feedback_id: int, body: FeedbackPatch, _: Admin = Depends(require_permission("feedback.manage"))):
    if body.status is not None and body.status not in STATUSES:
        raise HTTPException(422, f"status must be one of {', '.join(STATUSES)}")
    if body.status is None and body.admin_notes is None:
        raise HTTPException(422, "nothing to update")
    with db() as con:
        r = con.execute("SELECT * FROM user_feedbacks WHERE id=?", (feedback_id,)).fetchone()
        if r is None:
            raise HTTPException(404, "feedback not found")
        con.execute(
            "UPDATE user_feedbacks SET status=?, admin_notes=?, updated_at=? WHERE id=?",
            (body.status or r["status"], r["admin_notes"] if body.admin_notes is None else body.admin_notes,
             now(), feedback_id),
        )
        return _fb(con.execute("SELECT * FROM user_feedbacks WHERE id=?", (feedback_id,)).fetchone())
