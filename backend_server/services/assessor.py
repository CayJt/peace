"""Letter-level recitation assessment.

`EnergyAssessor` is a deterministic placeholder engine: it splits the PCM
stream into fixed windows (one per letter) and scores each window from its
loudness. It exists so the streaming protocol, client and tests are real; the
Whisper-based phoneme-alignment engine replaces it behind the same interface.
"""
from dataclasses import dataclass

import numpy as np

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

    def feed(self, pcm: bytes) -> list[LetterResult]:
        self._buf.extend(pcm)
        out: list[LetterResult] = []
        while len(self._buf) >= WINDOW_BYTES and not self.done:
            chunk = bytes(self._buf[:WINDOW_BYTES])
            del self._buf[:WINDOW_BYTES]
            out.append(self._score(chunk))
        return out

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
