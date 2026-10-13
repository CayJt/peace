import json

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from services import engine
from services.verse_provider import VerseNotFound, get_verse_provider
from services.whisper_model import SpeechUnavailable

router = APIRouter()


@router.websocket("/ws/assess-tajweed/{verse_key}")
async def assess_tajweed(ws: WebSocket, verse_key: str):
    await ws.accept()
    try:
        ref = get_verse_provider().get_reference(verse_key)
    except VerseNotFound:
        await ws.send_json({"event": "ERROR", "message": f"unknown verse {verse_key}"})
        await ws.close(code=4404)
        return
    try:
        assessor = engine.make_assessor(ref)
    except SpeechUnavailable as e:
        await ws.send_json({"event": "ERROR", "message": str(e)})
        await ws.close(code=1011)
        return

    scores: list[float] = []
    await ws.send_json({
        "event": "READY", "verse_key": verse_key, "letters": assessor.total, "engine": assessor.engine,
    })
    async def emit(results):
        for r in results:
            scores.append(r.score)
            await ws.send_json({
                "event": "LETTER_ASSESSED",
                "word_position": r.word_position,
                "letter_index": r.letter_index,
                "score": r.score,
                "status": r.status,
            })

    try:
        while True:
            msg = await ws.receive()
            if msg["type"] == "websocket.disconnect":
                return
            if msg.get("bytes") is not None:
                await emit(await assessor.feed(msg["bytes"]))
                if assessor.done:
                    break
            elif msg.get("text") is not None:
                try:
                    if json.loads(msg["text"]).get("event") == "END":
                        break
                except ValueError:
                    pass
        await emit(await assessor.finish())
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
