import json

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from services.arabic import letters_of
from services.assessor import EnergyAssessor
from services.verse_provider import VerseNotFound, get_verse_provider

router = APIRouter()


@router.websocket("/ws/assess-tajweed/{verse_key}")
async def assess_tajweed(ws: WebSocket, verse_key: str):
    await ws.accept()
    try:
        words = get_verse_provider().get_words(verse_key)
    except VerseNotFound:
        await ws.send_json({"event": "ERROR", "message": f"unknown verse {verse_key}"})
        await ws.close(code=4404)
        return

    assessor = EnergyAssessor([len(letters_of(w)) for w in words])
    scores: list[float] = []
    await ws.send_json({"event": "READY", "verse_key": verse_key, "letters": assessor.total})
    try:
        while True:
            msg = await ws.receive()
            if msg["type"] == "websocket.disconnect":
                return
            if msg.get("bytes") is not None:
                for r in assessor.feed(msg["bytes"]):
                    scores.append(r.score)
                    await ws.send_json({
                        "event": "LETTER_ASSESSED",
                        "word_position": r.word_position,
                        "letter_index": r.letter_index,
                        "score": r.score,
                        "status": r.status,
                    })
                if assessor.done:
                    break
            elif msg.get("text") is not None:
                try:
                    if json.loads(msg["text"]).get("event") == "END":
                        break
                except ValueError:
                    pass
        avg = round(sum(scores) / len(scores), 2) if scores else 0.0
        await ws.send_json({
            "event": "VERSE_SUMMARY",
            "verse_key": verse_key,
            "letters_assessed": len(scores),
            "average_score": avg,
        })
        await ws.close()
    except WebSocketDisconnect:
        return
