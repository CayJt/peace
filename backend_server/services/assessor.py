"""Letter-level recitation assessment engines (same async interface):

- `WhisperAssessor`: Whisper transcription aligned to the reference verse
  (recognition correctness per letter; see services/alignment.py for limits).
- `EnergyAssessor`: deterministic loudness-only fallback used when Whisper is
  unavailable, so the stream/protocol keeps working.
"""
import asyncio
import os
from dataclasses import dataclass

import numpy as np

from services.alignment import HypWord, align_words
from services.arabic import letters_of

SAMPLE_RATE = 16_000
WINDOW_MS = 120
WINDOW_BYTES = SAMPLE_RATE * WINDOW_MS // 1000 * 2  # PCM16 mono
PASS_THRESHOLD = 0.8
SILENCE_RMS = 200.0  # on int16 scale
FULL_RMS = 3000.0


@dataclass
class LetterResult:
    word_position: int
    letter_index: int
    score: float
    status: str


class EnergyAssessor:
    def __init__(self, letters_per_word: list[int]):
        self._slots = [
            (w + 1, i) for w, n in enumerate(letters_per_word) for i in range(n)
        ]
        self._buf = bytearray()
        self._next = 0

    @property
    def total(self) -> int:
        return len(self._slots)

    @property
    def done(self) -> bool:
        return self._next >= self.total

    async def feed(self, pcm: bytes) -> list[LetterResult]:
        self._buf.extend(pcm)
        out: list[LetterResult] = []
        while len(self._buf) >= WINDOW_BYTES and not self.done:
            chunk = bytes(self._buf[:WINDOW_BYTES])
            del self._buf[:WINDOW_BYTES]
            out.append(self._score(chunk))
        return out

    async def finish(self) -> list[LetterResult]:
        return []

    engine = "energy"

    def _score(self, chunk: bytes) -> LetterResult:
        x = np.frombuffer(chunk, dtype="<i2").astype(np.float64)
        rms = float(np.sqrt(np.mean(x * x))) if x.size else 0.0
        if rms < SILENCE_RMS:
            score = 0.0
        else:
            score = min(1.0, 0.5 + 0.5 * (rms - SILENCE_RMS) / (FULL_RMS - SILENCE_RMS))
        word_position, letter_index = self._slots[self._next]
        self._next += 1
        return LetterResult(
            word_position,
            letter_index,
            round(score, 2),
            "PASS" if score >= PASS_THRESHOLD else "NEED_RETRY",
        )


# ---------------------------------------------------------------- Whisper

PASS_THRESHOLD_WHISPER = float(os.environ.get("TAJWEED_PASS", "0.7"))
PASS_INTERVAL_S = 2.0   # re-transcribe after this much new audio
MIN_AUDIO_S = 1.0
GATE_RMS = 150.0        # below this the buffer is treated as silence


class WhisperAssessor:
    """Re-transcribes the growing buffer and commits words once they are stable.

    A reference word is *committed* (its letters emitted, in verse order) when
    it is aligned to a hypothesis word that is not the last one heard - the
    final hypothesis word may still change as more audio arrives. `finish()`
    commits everything left, scoring unrecognised words 0.
    """

    engine = "whisper"

    def __init__(
        self,
        ref_words: list[str],
        transcriber,
        pass_threshold: float = PASS_THRESHOLD_WHISPER,
        ref_match: list[str] | None = None,
    ):
        self._ref = ref_words
        self._match = ref_match or ref_words
        self._t = transcriber
        self._thr = pass_threshold
        self._pcm = bytearray()
        self._last_pass_len = 0
        self._busy = asyncio.Lock()
        self._emitted_words = 0
        self.passes = 0

    @property
    def total(self) -> int:
        return sum(len(letters_of(w)) for w in self._ref)

    @property
    def done(self) -> bool:
        return self._emitted_words >= len(self._ref)

    def _samples(self):
        return np.frombuffer(bytes(self._pcm), dtype="<i2").astype(np.float32) / 32768.0

    async def feed(self, pcm: bytes) -> list[LetterResult]:
        self._pcm.extend(pcm)
        new = len(self._pcm) - self._last_pass_len
        if (
            self.done
            or len(self._pcm) < MIN_AUDIO_S * SAMPLE_RATE * 2
            or new < PASS_INTERVAL_S * SAMPLE_RATE * 2
            or self._busy.locked()
        ):
            return []
        return await self._run(final=False)

    async def finish(self) -> list[LetterResult]:
        async with self._busy:
            return await self._transcribe_and_commit(final=True)

    async def _run(self, final: bool) -> list[LetterResult]:
        async with self._busy:
            return await self._transcribe_and_commit(final)

    async def _transcribe_and_commit(self, final: bool) -> list[LetterResult]:
        self._last_pass_len = len(self._pcm)
        if self.done:
            return []
        x = self._samples()
        hyp: list[HypWord] = []
        if x.size and float(np.sqrt(np.mean((x * 32768.0) ** 2))) >= GATE_RMS:
            hyp = await asyncio.to_thread(self._t.transcribe_words, x)
            self.passes += 1
        return self._commit(hyp, final)

    def _commit(self, hyp: list[HypWord], final: bool) -> list[LetterResult]:
        alignment = align_words(self._match, hyp, letter_refs=self._ref)
        out: list[LetterResult] = []
        last_hyp = len(hyp) - 1
        while self._emitted_words < len(self._ref):
            a = alignment[self._emitted_words]
            if not final:
                later_matched = any(
                    b.hyp_index is not None for b in alignment[self._emitted_words + 1 :]
                )
                stable = a.hyp_index is not None and a.hyp_index < last_hyp
                skipped = a.hyp_index is None and later_matched
                if not (stable or skipped):
                    break
            for k, score in enumerate(a.letter_scores):
                out.append(
                    LetterResult(
                        a.ref_index + 1, k, score, "PASS" if score >= self._thr else "NEED_RETRY"
                    )
                )
            self._emitted_words += 1
        return out
