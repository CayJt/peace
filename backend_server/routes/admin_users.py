import re
import sqlite3

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field, field_validator

from routes.admin_auth import admin_dict
from services.admin_security import (
    PERMISSIONS, ROLE_PRESETS, ROLES, Admin, get_current_admin, hash_password, load_permissions,
    primary_admin_id, require_permission, row_to_admin, validate_password, verify_password,
)
from services.db import db, iso, now

router = APIRouter(prefix="/api/v1/admin/administrators")
_USERNAME = re.compile(r"^[A-Za-z0-9_.-]{3,32}$")
_EMAIL = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


def _check_perms(perms: list[str] | None) -> list[str] | None:
    if perms is None:
        return None
    bad = [p for p in perms if p not in PERMISSIONS]
    if bad:
        raise HTTPException(422, f"unknown permissions: {', '.join(bad)}")
    return sorted(set(perms))


class AdminCreate(BaseModel):
    username: str
    email: str
    full_name: str = Field(min_length=1, max_length=100)
    password: str
    role: str = "custom"
    permissions: list[str] | None = None
    is_active: bool = True

    @field_validator("username")
    @classmethod
    def _u(cls, v):
        if not _USERNAME.match(v):
            raise ValueError("username must be 3-32 chars: letters, digits, . _ -")
        return v

    @field_validator("email")
    @classmethod
    def _e(cls, v):
        if not _EMAIL.match(v):
            raise ValueError("invalid email")
        return v.lower()

    @field_validator("role")
    @classmethod
    def _r(cls, v):
        if v not in ROLES:
            raise ValueError(f"role must be one of {', '.join(ROLES)}")
        return v


class AdminUpdate(BaseModel):
    email: str | None = None
    full_name: str | None = Field(default=None, min_length=1, max_length=100)
    role: str | None = None
    is_active: bool | None = None
    permissions: list[str] | None = None

    @field_validator("email")
    @classmethod
    def _e(cls, v):
        if v is not None and not _EMAIL.match(v):
            raise ValueError("invalid email")
        return v.lower() if v else v

    @field_validator("role")
    @classmethod
    def _r(cls, v):
        if v is not None and v not in ROLES:
            raise ValueError(f"role must be one of {', '.join(ROLES)}")
        return v


class PasswordIn(BaseModel):
    new_password: str
    current_password: str | None = None


def _view(con: sqlite3.Connection, row: sqlite3.Row) -> dict:
    d = admin_dict(row_to_admin(con, row))
    d["is_primary"] = row["id"] == primary_admin_id(con)
    d["created_at"], d["updated_at"] = iso(row["created_at"]), iso(row["updated_at"])
    return d


def _get(con: sqlite3.Connection, admin_id: int) -> sqlite3.Row:
    row = con.execute("SELECT * FROM admin_users WHERE id=?", (admin_id,)).fetchone()
    if row is None:
        raise HTTPException(404, "administrator not found")
    return row


def _active_supers(con: sqlite3.Connection, excluding: int | None = None) -> int:
    return con.execute(
        "SELECT COUNT(*) c FROM admin_users WHERE role='super_admin' AND is_active=1 AND id IS NOT ?",
        (excluding,),
    ).fetchone()["c"]


def _no_escalation(actor: Admin, role: str, perms: list[str]) -> None:
    """Only a Super Admin may mint Super Admins or grant rights the actor lacks."""
    if role == "super_admin" and not actor.is_super:
        raise HTTPException(403, "only a super admin can assign the super_admin role")
    missing = [p for p in perms if not actor.has(p)]
    if missing:
        raise HTTPException(403, f"cannot grant permissions you do not hold: {', '.join(missing)}")


def _set_perms(con: sqlite3.Connection, admin_id: int, perms: list[str]) -> None:
    con.execute("DELETE FROM admin_permissions WHERE admin_id=?", (admin_id,))
    con.executemany("INSERT INTO admin_permissions(admin_id,permission_key) VALUES(?,?)", [(admin_id, p) for p in perms])


@router.get("")
def list_admins(_: Admin = Depends(require_permission("admins.manage"))):
    with db() as con:
        rows = con.execute("SELECT * FROM admin_users ORDER BY id").fetchall()
        return {"administrators": [_view(con, r) for r in rows]}


@router.post("", status_code=201)
def create_admin(body: AdminCreate, actor: Admin = Depends(require_permission("admins.manage"))):
    validate_password(body.password)
    perms = _check_perms(body.permissions)
    if perms is None:
        perms = ROLE_PRESETS[body.role]
    if body.role == "super_admin":
        perms = list(PERMISSIONS)
    _no_escalation(actor, body.role, perms)
    t = now()
    with db() as con:
        try:
            cur = con.execute(
                "INSERT INTO admin_users(username,email,password_hash,full_name,role,is_active,"
                "password_changed_at,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?)",
                (body.username, body.email, hash_password(body.password), body.full_name.strip(),
                 body.role, int(body.is_active), t, t, t),
            )
        except sqlite3.IntegrityError:
            raise HTTPException(409, "username or email already exists")
        _set_perms(con, cur.lastrowid, perms)
        return _view(con, _get(con, cur.lastrowid))


@router.put("/{admin_id}")
def update_admin(admin_id: int, body: AdminUpdate, actor: Admin = Depends(require_permission("admins.manage"))):
    with db() as con:
        row = _get(con, admin_id)
        is_primary = admin_id == primary_admin_id(con)
        if row["role"] == "super_admin" and not actor.is_super:
            raise HTTPException(403, "only a super admin can modify a super admin")
        new_role = body.role or row["role"]
        new_active = row["is_active"] if body.is_active is None else int(body.is_active)
        if is_primary and (new_role != "super_admin" or not new_active):
            raise HTTPException(403, "the primary super admin cannot be demoted or deactivated")
        if admin_id == actor.id and (not new_active or new_role != row["role"]):
            raise HTTPException(400, "you cannot deactivate or change the role of your own account")
        if row["role"] == "super_admin" and (new_role != "super_admin" or not new_active) and _active_supers(con, admin_id) == 0:
            raise HTTPException(400, "at least one active super admin must remain")

        perms = _check_perms(body.permissions)
        if new_role == "super_admin":
            perms = list(PERMISSIONS)
        elif perms is None and body.role and body.role != row["role"]:
            perms = ROLE_PRESETS[new_role]
        _no_escalation(actor, new_role, perms or [])
        try:
            con.execute(
                "UPDATE admin_users SET email=?, full_name=?, role=?, is_active=?, updated_at=? WHERE id=?",
                (body.email or row["email"], (body.full_name or row["full_name"]).strip(), new_role,
                 new_active, now(), admin_id),
            )
        except sqlite3.IntegrityError:
            raise HTTPException(409, "email already exists")
        if perms is not None:
            # a non-super actor must not silently strip rights they cannot see either
            hidden = load_permissions(con, admin_id, row["role"]) - set(actor.permissions) if not actor.is_super else set()
            _set_perms(con, admin_id, sorted(set(perms) | hidden))
        return _view(con, _get(con, admin_id))


@router.put("/{admin_id}/password", status_code=204)
def set_password(admin_id: int, body: PasswordIn, actor: Admin = Depends(get_current_admin)):
    """Super admin may reset anyone; anyone may change their own (with current password)."""
    if not (actor.is_super or actor.id == admin_id):
        raise HTTPException(403, "only a super admin or the account owner can set this password")
    validate_password(body.new_password)
    with db() as con:
        row = _get(con, admin_id)
        if actor.id == admin_id:
            if not body.current_password or not verify_password(body.current_password, row["password_hash"]):
                raise HTTPException(403, "current password is incorrect")
        t = now()
        # bumping password_changed_at invalidates every token issued before the change
        con.execute(
            "UPDATE admin_users SET password_hash=?, password_changed_at=?, updated_at=? WHERE id=?",
            (hash_password(body.new_password), t, t, admin_id),
        )


@router.delete("/{admin_id}", status_code=204)
def delete_admin(admin_id: int, actor: Admin = Depends(require_permission("admins.manage"))):
    with db() as con:
        row = _get(con, admin_id)
        if admin_id == primary_admin_id(con):
            raise HTTPException(403, "the primary super admin cannot be deleted")
        if admin_id == actor.id:
            raise HTTPException(400, "you cannot delete your own account")
        if row["role"] == "super_admin" and not actor.is_super:
            raise HTTPException(403, "only a super admin can delete a super admin")
        if row["role"] == "super_admin" and row["is_active"] and _active_supers(con, admin_id) == 0:
            raise HTTPException(400, "at least one active super admin must remain")
        con.execute("DELETE FROM admin_users WHERE id=?", (admin_id,))
