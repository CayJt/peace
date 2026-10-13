import httpx
from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel

from services.guardrail import REFUSAL, extract_verse_keys, is_in_domain
from services.llm import Answerer, AnthropicAnswerer, LLMUnavailable, Transcriber, WhisperTranscriber

router = APIRouter()
API = "https://api.quran.com/api/v4"


class ChatRequest(BaseModel):
    text: str


def get_answerer() -> Answerer:
    return AnthropicAnswerer()


def get_transcriber() -> Transcriber:
    return WhisperTranscriber()


def get_verse_lookup():
    """Returns fn(verse_key) -> {verse_key,text,translation} | None (Quran.com v4, translation 33)."""

    def lookup(key: str):
        try:
            r = httpx.get(
                f"{API}/verses/by_key/{key}",
                params={"fields": "text_uthmani", "translations": "33"},
                timeout=10,
            )
            if r.status_code != 200:
                return None
            v = r.json()["verse"]
            tr = next((t["text"] for t in v.get("translations", [])), "")
            return {"verse_key": key, "text": v["text_uthmani"], "translation": tr}
        except (httpx.HTTPError, KeyError, ValueError):
            return None

    return lookup


def _respond(question: str, answerer: Answerer, lookup) -> dict:
    question = question.strip()
    if not question:
        raise HTTPException(422, "empty question")
    if not is_in_domain(question):
        return {"answer": REFUSAL, "referenced_verses": []}
    context = [v for k in extract_verse_keys(question) if (v := lookup(k))]
    try:
        out = answerer.answer(question, context)
    except (LLMUnavailable, httpx.HTTPError) as e:
        raise HTTPException(503, f"assistant unavailable: {e}") from e
    # Only verses we actually fetched may be cited: never trust model-supplied verse text.
    by_key = {v["verse_key"]: v for v in context}
    for k in out.get("verse_keys", []):
        if k not in by_key and (v := lookup(k)):
            by_key[k] = v
    cited = [by_key[k] for k in out.get("verse_keys", []) if k in by_key]
    return {"answer": out["answer"], "referenced_verses": cited}


@router.post("/api/v1/quran-chat")
async def quran_chat(
    request: Request,
    answerer: Answerer = Depends(get_answerer),
    transcriber: Transcriber = Depends(get_transcriber),
    lookup=Depends(get_verse_lookup),
):
    """JSON `{"text": ...}` or multipart with an `audio` file (transcribed by Whisper)."""
    question: str | None = None
    if request.headers.get("content-type", "").startswith("multipart/"):
        form = await request.form()
        audio = form.get("audio")
        if audio is not None and hasattr(audio, "read"):
            try:
                question = transcriber.transcribe(await audio.read(), audio.filename or "audio.wav")
            except LLMUnavailable as e:
                raise HTTPException(503, f"speech-to-text unavailable: {e}") from e
        else:
            question = form.get("text")
    else:
        try:
            question = ChatRequest(**(await request.json())).text
        except (ValueError, TypeError) as e:
            raise HTTPException(422, "body must be JSON with a 'text' field") from e
    if not question:
        raise HTTPException(422, "provide text or audio")
    return _respond(question, answerer, lookup)
