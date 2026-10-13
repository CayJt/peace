import asyncio
import threading

import numpy as np
import pytest

from services.alignment import HypWord
from services.assessor import SAMPLE_RATE, WhisperAssessor

REF = ["بِسْمِ", "ٱللَّهِ", "ٱلرَّحْمَٰنِ", "ٱلرَّحِيمِ"]  # 3, 4, 6, 6 letters
ALL = ["بسم", "الله", "الرحمن", "الرحيم"]


def audio(seconds, amp=3000):
    n = int(seconds * SAMPLE_RATE)
    return (amp * np.sin(2 * np.pi * 200 * np.arange(n) / SAMPLE_RATE)).astype("<i2").tobytes()


class Scripted:
    """Returns the first k words heard on pass k (growing hypothesis)."""

    def __init__(self, script):
        self.script, self.calls, self.threads = script, 0, set()

    def transcribe_words(self, samples):
        self.threads.add(threading.current_thread())
        words = self.script[min(self.calls, len(self.script) - 1)]
        self.calls += 1
        return [HypWord(w, i * 0.5, i * 0.5 + 0.4, 0.9) for i, w in enumerate(words)]


def run(coro):
    return asyncio.run(coro)


def test_commits_stable_words_only_and_in_order():
    async def go():
        t = Scripted([ALL[:2], ALL[:3], ALL])
        a = WhisperAssessor(REF, t)
        out1 = await a.feed(audio(2.1))          # heard 2 words: word 1 stable, word 2 is "last heard"
        out2 = await a.feed(audio(2.1))          # heard 3: word 2 now stable
        out3 = await a.feed(audio(2.1))          # heard 4: word 3 stable
        out4 = await a.finish()                  # rest committed
        return a, out1, out2, out3, out4

    a, o1, o2, o3, o4 = run(go())
    assert [(r.word_position, r.letter_index) for r in o1] == [(1, 0), (1, 1), (1, 2)]
    assert {r.word_position for r in o2} == {2} and len(o2) == 4
    assert {r.word_position for r in o3} == {3} and len(o3) == 6
    assert {r.word_position for r in o4} == {4} and len(o4) == 6
    assert a.done
    assert all(r.status == "PASS" and r.score == 0.9 for r in o1 + o2 + o3 + o4)


def test_no_pass_before_interval_or_min_audio():
    async def go():
        t = Scripted([ALL])
        a = WhisperAssessor(REF, t)
        assert await a.feed(audio(0.5)) == []
        assert await a.feed(audio(0.5)) == []   # 1.0 s total, but < 2 s of new audio
        return t.calls

    assert run(go()) == 0


def test_silence_is_gated_and_never_reaches_whisper():
    async def go():
        t = Scripted([ALL])
        a = WhisperAssessor(REF, t)
        await a.feed(audio(3, amp=0))
        out = await a.finish()
        return t.calls, out

    calls, out = run(go())
    assert calls == 0
    assert len(out) == 19 and all(r.score == 0.0 and r.status == "NEED_RETRY" for r in out)


def test_finish_scores_unrecited_words_zero():
    async def go():
        a = WhisperAssessor(REF, Scripted([ALL[:2]]))
        await a.feed(audio(2.1))
        return await a.finish()

    out = run(go())
    by_word = {}
    for r in out:
        by_word.setdefault(r.word_position, []).append(r.score)
    assert by_word[2] == [0.9] * 4            # last heard word, committed at finish
    assert by_word[3] == [0.0] * 6 and by_word[4] == [0.0] * 6


def test_skipped_word_is_committed_zero_once_later_word_is_stable():
    async def go():
        a = WhisperAssessor(REF, Scripted([["بسم", "الرحمن", "الرحيم"]]))
        return await a.feed(audio(2.1))

    out = run(go())
    words = {}
    for r in out:
        words.setdefault(r.word_position, []).append(r.score)
    assert words[1] == [0.9] * 3
    assert words[2] == [0.0] * 4              # skipped
    assert words[3] == [0.9] * 6              # stable (not last heard)
    assert 4 not in words                      # last heard: wait


def test_transcription_runs_off_the_event_loop_thread():
    t = Scripted([ALL])
    run((lambda: _go(t))())
    assert threading.main_thread() not in t.threads


async def _go(t):
    a = WhisperAssessor(REF, t)
    await a.feed(audio(2.1))


def test_pass_threshold_is_configurable():
    async def go():
        a = WhisperAssessor(REF, Scripted([ALL]), pass_threshold=0.95)
        await a.feed(audio(2.1))
        return await a.finish()

    assert all(r.status == "NEED_RETRY" for r in run(go()))


def test_overlapping_passes_are_skipped_not_queued():
    async def go():
        gate = threading.Event()

        class Slow:
            calls = 0

            def transcribe_words(self, s):
                Slow.calls += 1
                gate.wait(2)
                return []

        a = WhisperAssessor(REF, Slow())
        first = asyncio.create_task(a.feed(audio(2.1)))
        await asyncio.sleep(0.05)
        second = await a.feed(audio(2.1))   # lock held -> returns immediately
        gate.set()
        await first
        return second, Slow.calls

    second, calls = run(go())
    assert second == [] and calls == 1
