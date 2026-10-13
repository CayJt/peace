import numpy as np
import pytest
from fastapi.testclient import TestClient

from main import app
from services import verse_provider
from services.assessor import WINDOW_BYTES
from services.verse_provider import VerseNotFound

# Synthetic verse: two words with 2 and 3 base letters (marks must not count).
WORDS = ["بِسْ", "ٱللَّه"]  # ب س | ا ل ل ه  -> 2 + 4 letters


class FakeProvider:
    def get_reference(self, key):
        if key != "1:1":
            raise VerseNotFound(key)
        return [{"uthmani": w, "imlaei": w} for w in WORDS]


@pytest.fixture(autouse=True)
def _provider(monkeypatch):
    monkeypatch.setenv("TAJWEED_ENGINE", "energy")
    monkeypatch.setattr(verse_provider, "_default", FakeProvider())


def pcm(amplitude: int) -> bytes:
    n = WINDOW_BYTES // 2
    t = np.arange(n)
    return (amplitude * np.sin(2 * np.pi * 220 * t / 16000)).astype("<i2").tobytes()


client = TestClient(app)


def test_streams_letter_events_in_order():
    with client.websocket_connect("/ws/assess-tajweed/1:1") as ws:
        ready = ws.receive_json()
        assert ready["event"] == "READY" and ready["letters"] == 6 and ready["engine"] == "energy"
        ws.send_bytes(pcm(5000))
        ev = ws.receive_json()
        assert ev == {"event": "LETTER_ASSESSED", "word_position": 1, "letter_index": 0,
                      "score": 1.0, "status": "PASS"}
        ws.send_bytes(pcm(0))
        ev = ws.receive_json()
        assert (ev["word_position"], ev["letter_index"]) == (1, 1)
        assert ev["score"] == 0.0 and ev["status"] == "NEED_RETRY"


def test_summary_after_all_letters():
    with client.websocket_connect("/ws/assess-tajweed/1:1") as ws:
        ws.receive_json()
        ws.send_bytes(pcm(5000) * 6)
        events = [ws.receive_json() for _ in range(7)]
        assert [e["event"] for e in events[:6]] == ["LETTER_ASSESSED"] * 6
        assert events[6]["event"] == "VERSE_SUMMARY"
        assert events[6]["letters_assessed"] == 6 and events[6]["average_score"] == 1.0


def test_end_message_closes_with_summary():
    with client.websocket_connect("/ws/assess-tajweed/1:1") as ws:
        ws.receive_json()
        ws.send_text('{"event":"END"}')
        s = ws.receive_json()
        assert s["event"] == "VERSE_SUMMARY" and s["letters_assessed"] == 0


def test_unknown_verse():
    with pytest.raises(Exception):
        with client.websocket_connect("/ws/assess-tajweed/9:9") as ws:
            assert ws.receive_json()["event"] == "ERROR"
            ws.receive_json()


def test_whisper_engine_events_and_summary(monkeypatch):
    from services import engine
    from services.alignment import HypWord
    from services.assessor import WhisperAssessor

    class T:
        def transcribe_words(self, s):
            return [HypWord("بس", 0, 1, 0.9), HypWord("الله", 1, 2, 0.9)]

    monkeypatch.setattr(
        engine, "make_assessor",
        lambda ref: WhisperAssessor([w["uthmani"] for w in ref], T(), ref_match=[w["imlaei"] for w in ref]),
    )
    with client.websocket_connect("/ws/assess-tajweed/1:1") as ws:
        ready = ws.receive_json()
        assert ready["engine"] == "whisper" and ready["letters"] == 6
        ws.send_bytes(np.zeros(1, dtype="<i2").tobytes() + (np.full(16000 * 3, 3000, dtype="<i2")).tobytes())
        ws.send_text('{"event":"END"}')
        evs = []
        while True:
            e = ws.receive_json()
            evs.append(e)
            if e["event"] == "VERSE_SUMMARY":
                break
    letters = [e for e in evs if e["event"] == "LETTER_ASSESSED"]
    assert len(letters) == 6
    # "بِسْ" heard as "بس" -> both letters recognised; "ٱللَّه" heard "الله" -> 4 letters
    assert [e["score"] for e in letters] == [0.9] * 6
    assert evs[-1]["letters_assessed"] == 6 and evs[-1]["average_score"] == 0.9


def test_whisper_required_but_unavailable_is_an_error(monkeypatch):
    from services import engine, whisper_model

    monkeypatch.setenv("TAJWEED_ENGINE", "whisper")
    monkeypatch.setattr(engine, "_whisper_ok", None)
    monkeypatch.setattr(
        engine, "load_model",
        lambda: (_ for _ in ()).throw(whisper_model.SpeechUnavailable("no model")),
    )
    with client.websocket_connect("/ws/assess-tajweed/1:1") as ws:
        e = ws.receive_json()
        assert e["event"] == "ERROR" and "Whisper" in e["message"]


def test_auto_falls_back_to_energy(monkeypatch):
    from services import engine, whisper_model

    monkeypatch.setenv("TAJWEED_ENGINE", "auto")
    monkeypatch.setattr(engine, "_whisper_ok", None)
    monkeypatch.setattr(
        engine, "load_model",
        lambda: (_ for _ in ()).throw(whisper_model.SpeechUnavailable("no model")),
    )
    with client.websocket_connect("/ws/assess-tajweed/1:1") as ws:
        assert ws.receive_json()["engine"] == "energy"
