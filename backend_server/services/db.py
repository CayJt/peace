"""Single SQLite database shared by user auth, admin RBAC and operational logs."""
import os
import sqlite3
import time
from contextlib import contextmanager

DB_PATH = os.environ.get("QURAN_DB", "quran.db")

SCHEMA = """
CREATE TABLE IF NOT EXISTS users(
  id INTEGER PRIMARY KEY, email TEXT UNIQUE NOT NULL, full_name TEXT NOT NULL,
  salt BLOB NOT NULL, pw_hash BLOB NOT NULL, created_at REAL NOT NULL);
CREATE TABLE IF NOT EXISTS sessions(
  token_hash TEXT PRIMARY KEY, user_id INTEGER NOT NULL, created_at REAL NOT NULL);
CREATE TABLE IF NOT EXISTS user_heartbeats(
  user_id INTEGER PRIMARY KEY, last_seen REAL NOT NULL);
CREATE TABLE IF NOT EXISTS murajaah_sessions(
  id INTEGER PRIMARY KEY AUTOINCREMENT, user_id INTEGER NOT NULL, page INTEGER NOT NULL,
  duration_sec INTEGER NOT NULL, letters_evaluated INTEGER NOT NULL, score REAL NOT NULL,
  khatam_count INTEGER NOT NULL DEFAULT 0, created_at REAL NOT NULL);
CREATE INDEX IF NOT EXISTS idx_murajaah_user ON murajaah_sessions(user_id);

CREATE TABLE IF NOT EXISTS admin_users(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  username TEXT NOT NULL UNIQUE COLLATE NOCASE,
  email TEXT NOT NULL UNIQUE COLLATE NOCASE,
  password_hash TEXT NOT NULL,
  full_name TEXT NOT NULL,
  role TEXT NOT NULL CHECK(role IN ('super_admin','editor','auditor','custom')),
  is_active INTEGER NOT NULL DEFAULT 1,
  password_changed_at REAL NOT NULL,
  created_at REAL NOT NULL, updated_at REAL NOT NULL);
CREATE TABLE IF NOT EXISTS admin_permissions(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  admin_id INTEGER NOT NULL REFERENCES admin_users(id) ON DELETE CASCADE,
  permission_key TEXT NOT NULL,
  UNIQUE(admin_id, permission_key));
CREATE TABLE IF NOT EXISTS system_configs(
  key TEXT PRIMARY KEY, value TEXT NOT NULL,
  updated_by INTEGER REFERENCES admin_users(id) ON DELETE SET NULL,
  updated_at REAL NOT NULL);
CREATE TABLE IF NOT EXISTS chat_logs(
  id INTEGER PRIMARY KEY AUTOINCREMENT, user_id TEXT NOT NULL, question TEXT NOT NULL,
  answer TEXT NOT NULL, referenced_verses TEXT NOT NULL DEFAULT '[]',
  is_guardrail_triggered INTEGER NOT NULL DEFAULT 0, created_at REAL NOT NULL);
CREATE TABLE IF NOT EXISTS user_feedbacks(
  id INTEGER PRIMARY KEY AUTOINCREMENT, user_id TEXT NOT NULL,
  category TEXT NOT NULL CHECK(category IN ('bug','suggestion','content','other')),
  message TEXT NOT NULL, app_version TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT 'open' CHECK(status IN ('open','in_progress','resolved','discarded')),
  admin_notes TEXT NOT NULL DEFAULT '', created_at REAL NOT NULL, updated_at REAL NOT NULL);
CREATE INDEX IF NOT EXISTS idx_feedback_status ON user_feedbacks(status);
"""


@contextmanager
def db():
    """Connection with FK enforcement; commits on success, always closes."""
    con = sqlite3.connect(DB_PATH, timeout=10)
    con.row_factory = sqlite3.Row
    con.execute("PRAGMA foreign_keys = ON")
    con.executescript(SCHEMA)
    try:
        yield con
        con.commit()
    except Exception:
        con.rollback()
        raise
    finally:
        con.close()


def now() -> float:
    return time.time()


def iso(ts: float | None) -> str | None:
    if ts is None:
        return None
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(ts))
