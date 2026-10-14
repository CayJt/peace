import time

from fastapi import APIRouter, Depends, Query

from services import activity
from services.admin_security import Admin, require_permission
from services.db import db, iso, now

router = APIRouter(prefix="/api/v1/admin")
HEARTBEAT_WINDOW = 5 * 60


def _mask(email: str) -> str:
    name, _, dom = email.partition("@")
    return f"{name[:2]}***@{dom}"


@router.get("/analytics/realtime")
def realtime(_: Admin = Depends(require_permission("analytics.view"))):
    with db() as con:
        active = con.execute(
            "SELECT COUNT(*) c FROM user_heartbeats WHERE last_seen >= ?", (now() - HEARTBEAT_WINDOW,)
        ).fetchone()["c"]
        pending = con.execute("SELECT COUNT(*) c FROM user_feedbacks WHERE status='open'").fetchone()["c"]
    return {
        "active_users": active, "active_ws_connections": activity.active_ws,
        "window_seconds": HEARTBEAT_WINDOW, "pending_feedback": pending, "server_time": iso(now()),
    }


@router.get("/users/stats")
def user_stats(days: int = Query(30, ge=7, le=180), _: Admin = Depends(require_permission("users.view"))):
    day = 86400
    start = int(now() // day) * day - (days - 1) * day
    with db() as con:
        total = con.execute("SELECT COUNT(*) c FROM users").fetchone()["c"]
        rows = con.execute(
            "SELECT CAST(created_at/? AS INTEGER) d, COUNT(*) c FROM users WHERE created_at >= ? GROUP BY d",
            (day, start),
        ).fetchall()
    by_day = {r["d"] * day: r["c"] for r in rows}
    trend = [
        {"date": time.strftime("%Y-%m-%d", time.gmtime(start + i * day)), "count": by_day.get(start + i * day, 0)}
        for i in range(days)
    ]
    return {
        "total_users": total,
        "new_last_7d": sum(t["count"] for t in trend[-7:]),
        "new_last_30d": sum(t["count"] for t in trend[-30:]),
        "trend": trend,
    }


@router.get("/analytics/leaderboard")
def leaderboard(
    sort: str = Query("score", pattern="^(score|khatam)$"),
    limit: int = Query(20, ge=1, le=100),
    min_letters: int = Query(1, ge=0),
    _: Admin = Depends(require_permission("users.view")),
):
    order = "avg_score DESC, letters DESC" if sort == "score" else "khatam DESC, avg_score DESC"
    with db() as con:
        rows = con.execute(
            f"""SELECT u.id, u.full_name, u.email,
                   SUM(m.score * m.letters_evaluated) * 1.0 / NULLIF(SUM(m.letters_evaluated), 0) avg_score,
                   SUM(m.letters_evaluated) letters, COUNT(*) sessions,
                   MAX(m.khatam_count) khatam, MAX(m.created_at) last_active
                FROM murajaah_sessions m JOIN users u ON u.id = m.user_id
                GROUP BY u.id HAVING COALESCE(SUM(m.letters_evaluated), 0) >= ?
                ORDER BY {order} LIMIT ?""",
            (min_letters, limit),
        ).fetchall()
    return {
        "sort": sort,
        "entries": [
            {
                "rank": i + 1, "user_id": r["id"], "name": r["full_name"], "email": _mask(r["email"]),
                "avg_score": round(r["avg_score"] or 0.0, 4), "letters_evaluated": r["letters"],
                "sessions": r["sessions"], "khatam_count": r["khatam"], "last_active": iso(r["last_active"]),
            }
            for i, r in enumerate(rows)
        ],
    }
