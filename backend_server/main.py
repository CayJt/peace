import os
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from routes import (
    admin_analytics, admin_auth, admin_config, admin_operations, admin_users, auth, public, quran_ai, tajweed_ws,
)
from services.admin_security import seed_initial_admin


@asynccontextmanager
async def lifespan(_: FastAPI):
    seed_initial_admin()
    yield


app = FastAPI(title="Quran Backend", lifespan=lifespan)

# Bearer-token API (no cookies): allow local dev origins plus any in CORS_ORIGINS (comma-separated).
app.add_middleware(
    CORSMiddleware,
    allow_origins=[o.strip() for o in os.environ.get("CORS_ORIGINS", "").split(",") if o.strip()],
    allow_origin_regex=r"https?://(localhost|127\.0\.0\.1)(:\d+)?",
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE"],
    allow_headers=["Authorization", "Content-Type"],
)

for r in (
    tajweed_ws.router, quran_ai.router, auth.router, public.router, admin_auth.router, admin_users.router,
    admin_analytics.router, admin_config.router, admin_operations.router,
):
    app.include_router(r)


@app.get("/health")
def health() -> dict:
    return {"status": "ok", "service": "quran_backend"}
