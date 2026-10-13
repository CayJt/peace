"""Align a Whisper hypothesis to the reference verse and score it per letter.

Whisper is a speech *recogniser*: a letter scores high when it was recognised
as the expected letter with high confidence. This measures recitation
correctness (right words/letters, clear articulation); it does not model
tajweed rules (madd length, ghunnah, ...) - that needs a phoneme-level model.
"""
from dataclasses import dataclass
from difflib import SequenceMatcher

from services.arabic import norm_letters, norm_word

MATCH_MIN_SIM = 0.5
GAP = -0.6


@dataclass
class HypWord:
    text: str
    start: float
    end: float
    prob: float  # 0..1 recognition confidence


@dataclass
class WordAlignment:
    ref_index: int
    hyp_index: int | None  # None: word was not recognised
    sim: float
    letter_scores: list[float]


def _sim(a: str, b: str) -> float:
    if not a or not b:
        return 0.0
    return SequenceMatcher(None, a, b).ratio()


def align_words(
    ref_words: list[str], hyp: list[HypWord], letter_refs: list[str] | None = None
) -> list[WordAlignment]:
    """Needleman-Wunsch over normalised words.

    `ref_words` are matched against the hypothesis (Imlaei spelling works best);
    `letter_refs` (default: ref_words) are the displayed words whose letters get
    scores - the slot count must be that of the displayed word.
    """
    letter_refs = letter_refs or ref_words
    r = [norm_word(w) for w in ref_words]
    h = [norm_word(w.text) for w in hyp]
    n, m = len(r), len(h)
    sims = [[_sim(r[i], h[j]) for j in range(m)] for i in range(n)]

    def sub(i: int, j: int) -> float:
        return sims[i][j] if sims[i][j] >= MATCH_MIN_SIM else -1.0

    dp = [[0.0] * (m + 1) for _ in range(n + 1)]
    for i in range(1, n + 1):
        dp[i][0] = i * GAP
    for j in range(1, m + 1):
        dp[0][j] = j * GAP
    for i in range(1, n + 1):
        for j in range(1, m + 1):
            dp[i][j] = max(
                dp[i - 1][j - 1] + sub(i - 1, j - 1),
                dp[i - 1][j] + GAP,
                dp[i][j - 1] + GAP,
            )

    pairs: dict[int, int | None] = {i: None for i in range(n)}
    i, j = n, m
    while i > 0 and j > 0:
        if dp[i][j] == dp[i - 1][j - 1] + sub(i - 1, j - 1):
            if sims[i - 1][j - 1] >= MATCH_MIN_SIM:
                pairs[i - 1] = j - 1
            i, j = i - 1, j - 1
        elif dp[i][j] == dp[i - 1][j] + GAP:
            i -= 1
        else:
            j -= 1

    out = []
    for i in range(n):
        j = pairs[i]
        if j is None:
            out.append(WordAlignment(i, None, 0.0, [0.0] * len(norm_letters(letter_refs[i]))))
        else:
            out.append(WordAlignment(i, j, sims[i][j], _letter_scores(ref_words[i], letter_refs[i], hyp[j])))
    return out


def _letter_scores(match_word: str, shown_word: str, hyp_word: HypWord) -> list[float]:
    """Scores indexed by the *displayed* word's letters. Letters are matched
    through the match-spelling and mapped back by order of appearance."""
    ref = norm_letters(match_word)
    hyp = norm_letters(hyp_word.text)
    shown = norm_letters(shown_word)
    scores = [0.0] * len(shown)
    conf = max(0.0, min(1.0, hyp_word.prob))
    matched: set[int] = set()
    for tag, i1, i2, _, _ in SequenceMatcher(None, ref, hyp, autojunk=False).get_opcodes():
        if tag == "equal":
            for k in range(i1, i2):
                matched.add(k)
    # map matched match-spelling letters onto displayed letters
    if len(shown) == len(ref):
        for k in matched:
            scores[k] = round(conf, 2)
    else:
        sm = SequenceMatcher(None, ref, shown, autojunk=False)
        for tag, i1, i2, j1, j2 in sm.get_opcodes():
            if tag == "equal":
                for off in range(i2 - i1):
                    if i1 + off in matched:
                        scores[j1 + off] = round(conf, 2)
    return scores
