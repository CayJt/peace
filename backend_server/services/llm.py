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
    """Chat speech-to-text via the shared faster-whisper model (language auto-detected)."""

    def transcribe(self, audio: bytes, filename: str) -> str:
        import subprocess

        import numpy as np

        from services.whisper_model import FasterWhisperTranscriber, SpeechUnavailable

        try:
            # ffmpeg decodes any container to 16 kHz mono float PCM
            raw = subprocess.run(
                ["ffmpeg", "-v", "error", "-i", "pipe:0", "-f", "s16le", "-ac", "1", "-ar", "16000", "pipe:1"],
                input=audio, capture_output=True, check=True, timeout=60,
            ).stdout
            samples = np.frombuffer(raw, dtype="<i2").astype(np.float32) / 32768.0
            return FasterWhisperTranscriber(language=None).transcribe_text(samples)
        except SpeechUnavailable as e:
            raise LLMUnavailable(str(e)) from e
        except (subprocess.SubprocessError, FileNotFoundError) as e:
            raise LLMUnavailable(f"cannot decode audio: {e}") from e
