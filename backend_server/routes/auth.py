import hashlib
import hmac
import os
import re
import secrets
import sqlite3
import time

from fastapi import APIRouter, Header, HTTPException
from pydantic import BaseModel

router = APIRouter(prefix="/api/v1/auth")
DB_PATH = os.environ.get("QURAN_DB", "quran.db")
_EMAIL = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


def _db() -> sqlite3.Connection:
    con = sqlite3.connect(DB_PATH)
    con.row_factory = sqlite3.Row
    con.executescript(
        """
        CREATE TABLE IF NOT EXISTS users(
          id INTEGER PRIMARY KEY, email TEXT UNIQUE NOT NULL, full_name TEXT NOT NULL,
          salt BLOB NOT NULL, pw_hash BLOB NOT NULL, created_at REAL NOT NULL);
        CREATE TABLE IF NOT EXISTS sessions(
          token_hash TEXT PRIMARY KEY, user_id INTEGER NOT NULL, created_at REAL NOT NULL);
        """
    )
    return con


def _hash(pw: str, salt: bytes) -> bytes:
    return hashlib.pbkdf2_hmac("sha256", pw.encode(), salt, 200_000)


def _issue(con: sqlite3.Connection, user_id: int) -> str:
    token = secrets.token_urlsafe(32)
    con.execute(
        "INSERT INTO sessions VALUES(?,?,?)",
        (hashlib.sha256(token.encode()).hexdigest(), user_id, time.time()),
    )
    con.commit()
    return token


class RegisterIn(BaseModel):
    email: str
    full_name: str
    password: str


class LoginIn(BaseModel):
    username: str  # email
    password: str


@router.post("/register", status_code=201)
def register(body: RegisterIn):
    if not _EMAIL.match(body.email):
        raise HTTPException(422, "invalid email")
    if len(body.password) < 8:
        raise HTTPException(422, "password must be at least 8 characters")
    if not body.full_name.strip():
        raise HTTPException(422, "full name required")
    con = _db()
    salt = os.urandom(16)
    try:
        cur = con.execute(
            "INSERT INTO users(email,full_name,salt,pw_hash,created_at) VALUES(?,?,?,?,?)",
            (body.email.lower(), body.full_name.strip(), salt, _hash(body.password, salt), time.time()),
        )
    except sqlite3.IntegrityError:
        raise HTTPException(409, "email already registered")
    token = _issue(con, cur.lastrowid)
    return {"token": token, "user": {"email": body.email.lower(), "full_name": body.full_name.strip()}}


@router.post("/login")
def login(body: LoginIn):
    con = _db()
    row = con.execute("SELECT * FROM users WHERE email=?", (body.username.lower(),)).fetchone()
    # Always hash so unknown users and wrong passwords take comparable time.
    salt = row["salt"] if row else b"\0" * 16
    ok = hmac.compare_digest(_hash(body.password, salt), row["pw_hash"] if row else b"\0" * 32)
    if not row or not ok:
        raise HTTPException(401, "invalid credentials")
    return {"token": _issue(con, row["id"]), "user": {"email": row["email"], "full_name": row["full_name"]}}


@router.post("/logout", status_code=204)
def logout(authorization: str = Header("")):
    token = authorization.removeprefix("Bearer ").strip()
    con = _db()
    con.execute("DELETE FROM sessions WHERE token_hash=?", (hashlib.sha256(token.encode()).hexdigest(),))
    con.commit()


@router.get("/me")
def me(authorization: str = Header("")):
    token = authorization.removeprefix("Bearer ").strip()
    con = _db()
    row = con.execute(
        "SELECT u.email,u.full_name FROM sessions s JOIN users u ON u.id=s.user_id WHERE s.token_hash=?",
        (hashlib.sha256(token.encode()).hexdigest(),),
    ).fetchone()
    if not row:
        raise HTTPException(401, "invalid token")
    return {"email": row["email"], "full_name": row["full_name"]}
