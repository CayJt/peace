"""Shared, lazily-loaded faster-whisper model + the Transcriber used by the assessor."""
import os
import threading
from typing import Protocol

import numpy as np

from services.alignment import HypWord


class SpeechUnavailable(Exception):
    pass


class WordTranscriber(Protocol):
    def transcribe_words(self, samples: np.ndarray) -> list[HypWord]:
        """samples: mono float32 in [-1, 1] at 16 kHz."""
        ...


_lock = threading.Lock()
_model = None


def load_model():
    """Loads once. WHISPER_MODEL: size name or path to a CTranslate2 model dir."""
    global _model
    with _lock:
        if _model is None:
            try:
                from faster_whisper import WhisperModel  # type: ignore
            except ImportError as e:
                raise SpeechUnavailable("faster-whisper not installed") from e
            name = os.environ.get("WHISPER_MODEL", "small")
            try:
                _model = WhisperModel(
                    name,
                    device=os.environ.get("WHISPER_DEVICE", "auto"),
                    compute_type=os.environ.get("WHISPER_COMPUTE", "int8"),
                    download_root=os.environ.get("WHISPER_CACHE"),
                )
            except Exception as e:  # download/format/OOM errors
                raise SpeechUnavailable(f"cannot load Whisper model '{name}': {e}") from e
        return _model


class FasterWhisperTranscriber:
    """Arabic word-timestamp transcription. No initial_prompt on purpose: priming
    with the expected verse would make Whisper echo it and inflate scores."""

    def __init__(self, language: str | None = "ar"):
        self.language = language

    def transcribe_words(self, samples: np.ndarray) -> list[HypWord]:
        model = load_model()
        segments, _ = model.transcribe(
            samples,
            language=self.language,
            word_timestamps=True,
            beam_size=1,
            condition_on_previous_text=False,
            vad_filter=False,
        )
        words: list[HypWord] = []
        for seg in segments:
            # drop likely hallucinations on silence/noise
            if seg.no_speech_prob > 0.6 and seg.avg_logprob < -1.0:
                continue
            for w in seg.words or []:
                words.append(HypWord(w.word.strip(), w.start, w.end, float(w.probability)))
        return words

    def transcribe_text(self, samples: np.ndarray) -> str:
        return " ".join(w.text for w in self.transcribe_words(samples))
