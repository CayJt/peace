"""Score a real recording against a verse - run this on a machine that can
download the Whisper model and reach api.quran.com:

    cd backend_server && python -m tools.assess_wav recitation.wav 1:1
"""
import asyncio
import subprocess
import sys

from services import engine
from services.assessor import SAMPLE_RATE
from services.verse_provider import get_verse_provider


async def main(path: str, verse_key: str) -> None:
    pcm = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", path, "-f", "s16le", "-ac", "1", "-ar", str(SAMPLE_RATE), "pipe:1"],
        capture_output=True, check=True,
    ).stdout
    ref = get_verse_provider().get_reference(verse_key)
    a = engine.make_assessor(ref)
    print(f"engine={a.engine} letters={a.total}")
    results = []
    step = SAMPLE_RATE * 2 // 2  # 0.5 s chunks, like a live stream
    for i in range(0, len(pcm), step):
        results += await a.feed(pcm[i : i + step])
    results += await a.finish()
    for w, word in enumerate(ref, start=1):
        rs = [r for r in results if r.word_position == w]
        print(f"{w:>2} {word['uthmani']:<14} " + " ".join(f"{r.score:.2f}{'' if r.status == 'PASS' else '!'}" for r in rs))
    if results:
        print(f"average={sum(r.score for r in results) / len(results):.2f}")


if __name__ == "__main__":
    asyncio.run(main(sys.argv[1], sys.argv[2]))
