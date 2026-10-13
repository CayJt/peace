"""LLM + Whisper adapters. Both are optional and injected so tests need no network."""
import json
import os
from typing import Protocol

import httpx

from services.guardrail import SYSTEM_PROMPT


class Answerer(Protocol):
    def answer(self, question: str, context: list[dict]) -> dict: ...


class Transcriber(Protocol):
    def transcribe(self, audio: bytes, filename: str) -> str: ...


class LLMUnavailable(Exception):
    pass


class AnthropicAnswerer:
    def __init__(self, api_key: str | None = None, model: str | None = None):
        self.api_key = api_key or os.environ.get("ANTHROPIC_API_KEY")
        self.model = model or os.environ.get("QURAN_CHAT_MODEL", "claude-sonnet-5-5")

    def answer(self, question: str, context: list[dict]) -> dict:
        if not self.api_key:
            raise LLMUnavailable("ANTHROPIC_API_KEY not set")
        ctx = "\n".join(f"{v['verse_key']}: {v['text']} — {v['translation']}" for v in context)
        r = httpx.post(
            "https://api.anthropic.com/v1/messages",
            headers={"x-api-key": self.api_key, "anthropic-version": "2023-06-01"},
            json={
                "model": self.model,
                "max_tokens": 1024,
                "system": SYSTEM_PROMPT,
                "messages": [{"role": "user", "content": f"Context verses:\n{ctx}\n\nQuestion: {question}"}],
            },
            timeout=30,
        )
        r.raise_for_status()
        text = r.json()["content"][0]["text"]
        try:
            data = json.loads(text)
            return {"answer": data["answer"], "verse_keys": data.get("verse_keys", [])}
        except (ValueError, KeyError):
            return {"answer": text, "verse_keys": []}


class WhisperTranscriber:
    """Uses faster-whisper when installed (not in requirements; heavy)."""

    def __init__(self, model_size: str = "small"):
        self.model_size = model_size
        self._model = None

    def transcribe(self, audio: bytes, filename: str) -> str:
        try:
            from faster_whisper import WhisperModel  # type: ignore
        except ImportError as e:
            raise LLMUnavailable("faster-whisper not installed") from e
        import tempfile

        if self._model is None:
            self._model = WhisperModel(self.model_size)
        with tempfile.NamedTemporaryFile(suffix=os.path.splitext(filename)[1] or ".wav") as f:
            f.write(audio)
            f.flush()
            segs, _ = self._model.transcribe(f.name)
            return " ".join(s.text for s in segs).strip()
