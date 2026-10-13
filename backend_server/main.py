from fastapi import FastAPI

app = FastAPI(title="Quran Backend")


@app.get("/health")
def health() -> dict:
    return {"status": "ok", "service": "quran_backend"}
