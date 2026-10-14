from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel

from services.admin_security import (
    PERMISSIONS, TOKEN_TTL, Admin, check_throttle, clear_failures, create_token, get_current_admin,
    pw_version, record_failure, row_to_admin, throttle_key, verify_password,
)
from services.db import db, iso

router = APIRouter(prefix="/api/v1/admin")


class LoginIn(BaseModel):
    username: str
    password: str


def admin_dict(a: Admin) -> dict:
    return {
        "id": a.id, "username": a.username, "email": a.email, "full_name": a.full_name,
        "role": a.role, "is_active": a.is_active, "permissions": sorted(a.permissions),
    }


@router.post("/auth/login")
def login(body: LoginIn, request: Request):
    key = throttle_key(request, body.username)
    check_throttle(key)
    with db() as con:
        row = con.execute("SELECT * FROM admin_users WHERE username=?", (body.username,)).fetchone()
        ok = verify_password(body.password, row["password_hash"] if row else None)
        if not (row and ok and row["is_active"]):
            record_failure(key)
            raise HTTPException(401, "invalid credentials")
        clear_failures(key)
        admin = row_to_admin(con, row)
        token = create_token(row["id"], pw_version(row["password_changed_at"]))
    return {
        "token": token, "token_type": "bearer", "expires_in": TOKEN_TTL,
        "admin": admin_dict(admin), "permissions": sorted(admin.permissions),
    }


@router.get("/auth/me")
def me(admin: Admin = Depends(get_current_admin)):
    return admin_dict(admin)


@router.get("/permissions-list")
def permissions_list(_: Admin = Depends(get_current_admin)):
    return {"permissions": [{"key": k, "label": v} for k, v in PERMISSIONS.items()]}
