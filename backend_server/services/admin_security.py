"""Admin authentication (bcrypt + JWT) and RBAC guards."""
import logging
import os
import secrets
import sqlite3
import time
from dataclasses import dataclass, field

import bcrypt
import jwt
from fastapi import Depends, HTTPException, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from services.db import db, now

log = logging.getLogger("admin")

PERMISSIONS: dict[str, str] = {
    "analytics.view": "Lihat analitik realtime",
    "users.view": "Lihat statistik pengguna & leaderboard",
    "config.manage": "Kelola konfigurasi (provider Al-Qur'an, cache)",
    "chats.view": "Lihat log chat AI & guardrail",
    "murajaah.view": "Lihat aktivitas murajaah pengguna",
    "feedback.manage": "Kelola kotak saran",
    "admins.manage": "Kelola akun administrator",
}
ROLES = ("super_admin", "editor", "auditor", "custom")
ROLE_PRESETS: dict[str, list[str]] = {
    "super_admin": list(PERMISSIONS),
    "editor": ["analytics.view", "users.view", "config.manage", "murajaah.view", "feedback.manage"],
    "auditor": ["analytics.view", "users.view", "chats.view", "murajaah.view"],
    "custom": [],
}

TOKEN_TTL = int(os.environ.get("ADMIN_TOKEN_TTL", str(8 * 3600)))
_JWT_ALG = "HS256"
_secret: str | None = None


def jwt_secret() -> str:
    """ADMIN_JWT_SECRET, else a random per-process secret (tokens die on restart)."""
    global _secret
    if _secret is None:
        _secret = os.environ.get("ADMIN_JWT_SECRET") or ""
        if len(_secret) < 32:
            if _secret:
                log.warning("ADMIN_JWT_SECRET is shorter than 32 chars; ignoring it")
            log.warning("ADMIN_JWT_SECRET not set: using a random secret; admin sessions end on restart")
            _secret = secrets.token_urlsafe(48)
    return _secret


# ---- passwords -------------------------------------------------------------

MIN_PW, MAX_PW_BYTES = 8, 72  # bcrypt ignores/rejects input beyond 72 bytes


def validate_password(pw: str) -> None:
    if len(pw) < MIN_PW:
        raise HTTPException(422, f"password must be at least {MIN_PW} characters")
    if len(pw.encode()) > MAX_PW_BYTES:
        raise HTTPException(422, f"password must be at most {MAX_PW_BYTES} bytes")


BCRYPT_ROUNDS = int(os.environ.get("ADMIN_BCRYPT_ROUNDS", "12"))  # tests lower this for speed


def hash_password(pw: str) -> str:
    return bcrypt.hashpw(pw.encode(), bcrypt.gensalt(rounds=BCRYPT_ROUNDS)).decode()


_DUMMY_HASH = hash_password("dummy-password")


def verify_password(pw: str, hashed: str | None) -> bool:
    """Always performs one bcrypt check so unknown users cost the same as wrong passwords."""
    try:
        ok = bcrypt.checkpw(pw.encode()[:MAX_PW_BYTES], (hashed or _DUMMY_HASH).encode())
    except ValueError:
        return False
    return ok and hashed is not None


# ---- login throttling ------------------------------------------------------

_fails: dict[str, list[float]] = {}
MAX_FAILS, WINDOW = 5, 15 * 60


def throttle_key(request: Request, username: str) -> str:
    ip = request.client.host if request.client else "?"
    return f"{ip}|{username.lower()}"


def check_throttle(key: str) -> None:
    recent = [t for t in _fails.get(key, []) if now() - t < WINDOW]
    _fails[key] = recent
    if len(recent) >= MAX_FAILS:
        raise HTTPException(429, "too many failed attempts, try again later")


def record_failure(key: str) -> None:
    _fails.setdefault(key, []).append(now())


def clear_failures(key: str) -> None:
    _fails.pop(key, None)


# ---- tokens ----------------------------------------------------------------

def create_token(admin_id: int, pw_version: int) -> str:
    t = int(time.time())
    return jwt.encode(
        {"sub": str(admin_id), "typ": "admin", "pwv": pw_version, "iat": t, "exp": t + TOKEN_TTL},
        jwt_secret(),
        algorithm=_JWT_ALG,
    )


def pw_version(ts: float) -> int:
    return int(ts * 1000)


# ---- current admin ---------------------------------------------------------

@dataclass
class Admin:
    id: int
    username: str
    email: str
    full_name: str
    role: str
    is_active: bool
    permissions: set[str] = field(default_factory=set)

    @property
    def is_super(self) -> bool:
        return self.role == "super_admin"

    def has(self, key: str) -> bool:
        return self.is_super or key in self.permissions


def load_permissions(con: sqlite3.Connection, admin_id: int, role: str) -> set[str]:
    if role == "super_admin":
        return set(PERMISSIONS)
    rows = con.execute("SELECT permission_key FROM admin_permissions WHERE admin_id=?", (admin_id,)).fetchall()
    return {r["permission_key"] for r in rows if r["permission_key"] in PERMISSIONS}


def row_to_admin(con: sqlite3.Connection, row: sqlite3.Row) -> Admin:
    return Admin(
        row["id"], row["username"], row["email"], row["full_name"], row["role"],
        bool(row["is_active"]), load_permissions(con, row["id"], row["role"]),
    )


_bearer = HTTPBearer(auto_error=False)


def get_current_admin(cred: HTTPAuthorizationCredentials | None = Depends(_bearer)) -> Admin:
    if cred is None:
        raise HTTPException(401, "missing bearer token", headers={"WWW-Authenticate": "Bearer"})
    try:
        claims = jwt.decode(
            cred.credentials, jwt_secret(), algorithms=[_JWT_ALG], options={"require": ["exp", "sub", "pwv"]}
        )
        if claims.get("typ") != "admin":
            raise jwt.InvalidTokenError("wrong token type")
        admin_id = int(claims["sub"])
    except (jwt.PyJWTError, ValueError):
        raise HTTPException(401, "invalid or expired token", headers={"WWW-Authenticate": "Bearer"})
    with db() as con:
        row = con.execute("SELECT * FROM admin_users WHERE id=?", (admin_id,)).fetchone()
        # State is read fresh on every request: deactivation, role/permission edits and
        # password resets take effect immediately (pwv ties a token to the password).
        if row is None or not row["is_active"] or pw_version(row["password_changed_at"]) != claims["pwv"]:
            raise HTTPException(401, "invalid or expired token", headers={"WWW-Authenticate": "Bearer"})
        return row_to_admin(con, row)


def require_permission(permission_key: str):
    if permission_key not in PERMISSIONS:
        raise ValueError(f"unknown permission {permission_key}")

    def guard(admin: Admin = Depends(get_current_admin)) -> Admin:
        if not admin.has(permission_key):
            raise HTTPException(403, f"missing permission: {permission_key}")
        return admin

    return guard


# ---- helpers & seeding -----------------------------------------------------

def primary_admin_id(con: sqlite3.Connection) -> int | None:
    r = con.execute("SELECT MIN(id) m FROM admin_users WHERE role='super_admin'").fetchone()
    return r["m"]


def seed_initial_admin() -> str | None:
    """Create the first Super Admin if none exist. Returns a generated password, if any."""
    generated: str | None = None
    with db() as con:
        con.execute(
            "INSERT OR IGNORE INTO system_configs(key,value,updated_at) VALUES('quran_data_provider','quran.com',?)",
            (now(),),
        )
        if con.execute("SELECT COUNT(*) c FROM admin_users").fetchone()["c"]:
            return None
        pw = os.environ.get("INITIAL_ADMIN_PASSWORD")
        if not pw:
            pw = generated = secrets.token_urlsafe(12)
        elif len(pw) < MIN_PW or len(pw.encode()) > MAX_PW_BYTES:
            raise RuntimeError("INITIAL_ADMIN_PASSWORD must be 8-72 bytes")
        t = now()
        cur = con.execute(
            "INSERT INTO admin_users(username,email,password_hash,full_name,role,is_active,"
            "password_changed_at,created_at,updated_at) VALUES(?,?,?,?,?,1,?,?,?)",
            ("admin", os.environ.get("INITIAL_ADMIN_EMAIL", "admin@localhost.local"), hash_password(pw),
             "Super Administrator", "super_admin", t, t, t),
        )
        con.executemany(
            "INSERT INTO admin_permissions(admin_id,permission_key) VALUES(?,?)",
            [(cur.lastrowid, k) for k in PERMISSIONS],
        )
    if generated:
        print(
            f"\n[admin] First start: created Super Admin 'admin' with TEMPORARY password: {generated}\n"
            "[admin] Log in and change it now (this is printed once).\n",
            flush=True,
        )
    return generated
