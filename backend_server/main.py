from fastapi import FastAPI

from routes import auth, quran_ai, tajweed_ws

app = FastAPI(title="Quran Backend")
app.include_router(tajweed_ws.router)
app.include_router(quran_ai.router)
app.include_router(auth.router)


@app.get("/health")
def health() -> dict:
    return {"status": "ok", "service": "quran_backend"}
