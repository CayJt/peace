"""Chooses the assessment engine. TAJWEED_ENGINE=whisper|energy|auto (default auto).

auto: Whisper if faster-whisper imports and the model loads, else energy.
The chosen engine is reported to the client in the READY event.
"""
import logging
import os

from services.assessor import EnergyAssessor, WhisperAssessor
from services.arabic import letters_of
from services.whisper_model import FasterWhisperTranscriber, SpeechUnavailable, load_model

log = logging.getLogger("tajweed")
_transcriber = None
_whisper_ok: bool | None = None


def _whisper_available() -> bool:
    global _whisper_ok
    if _whisper_ok is None:
        try:
            load_model()
            _whisper_ok = True
        except SpeechUnavailable as e:
            log.warning("Whisper unavailable, using energy engine: %s", e)
            _whisper_ok = False
    return _whisper_ok


def make_assessor(ref: list[dict]):
    """ref: [{"uthmani":..., "imlaei":...}, ...]"""
    global _transcriber
    choice = os.environ.get("TAJWEED_ENGINE", "auto")
    if choice != "energy" and _whisper_available():
        _transcriber = _transcriber or FasterWhisperTranscriber("ar")
        # Match against Imlaei spelling (what Whisper writes); letters/scores
        # stay indexed by the Uthmani word the client displays.
        return WhisperAssessor([w["uthmani"] for w in ref], _transcriber, ref_match=[w["imlaei"] for w in ref])
    if choice == "whisper":
        raise SpeechUnavailable("TAJWEED_ENGINE=whisper but Whisper cannot be loaded")
    return EnergyAssessor([len(letters_of(w["uthmani"])) for w in ref])
