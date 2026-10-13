from services.alignment import HypWord, align_words
from services.arabic import norm_word


def hyp(*words, prob=0.9):
    return [HypWord(w, i * 0.5, i * 0.5 + 0.4, prob) for i, w in enumerate(words)]


REF = ["بِسْمِ", "ٱللَّهِ", "ٱلرَّحْمَٰنِ", "ٱلرَّحِيمِ"]


def test_normalisation_merges_spelling_variants():
    assert norm_word("ٱللَّهِ") == norm_word("الله") == "الله"
    assert norm_word("إِلَٰهَ") == norm_word("اله")
    assert norm_word("مُوسَىٰ") == norm_word("موسي")


def test_perfect_recitation_scores_every_letter():
    al = align_words(REF, hyp("بسم", "الله", "الرحمن", "الرحيم", prob=0.95))
    assert [a.hyp_index for a in al] == [0, 1, 2, 3]
    assert [len(a.letter_scores) for a in al] == [3, 4, 6, 6]
    assert all(s == 0.95 for a in al for s in a.letter_scores)


def test_missing_word_scores_zero_and_neighbours_unaffected():
    al = align_words(REF, hyp("بسم", "الرحمن", "الرحيم"))
    assert al[1].hyp_index is None and al[1].letter_scores == [0.0] * 4
    assert al[0].hyp_index == 0 and al[2].hyp_index == 1 and al[3].hyp_index == 2


def test_extra_hypothesis_word_is_ignored():
    al = align_words(REF, hyp("بسم", "هذا", "الله", "الرحمن", "الرحيم"))
    assert [a.hyp_index for a in al] == [0, 2, 3, 4]


def test_wrong_letter_loses_only_that_letter():
    # ref الرحمن (6 letters) heard as الرخمن: ح->خ
    al = align_words(["ٱلرَّحْمَٰنِ"], hyp("الرخمن"))
    s = al[0].letter_scores
    assert al[0].hyp_index == 0
    assert s.count(0.0) == 1 and len(s) == 6 and s[3] == 0.0


def test_unrelated_word_is_not_matched():
    al = align_words(["بِسْمِ"], hyp("قلم"))
    assert al[0].hyp_index is None


def test_empty_hypothesis():
    al = align_words(REF, [])
    assert all(a.hyp_index is None and not any(a.letter_scores) for a in al)


def test_imlaei_matching_with_uthmani_letter_slots():
    # Uthmani has 5 letter slots (no alef after ص); Imlaei spelling has the alef.
    shown = "ٱلصِّرَٰطَ"
    match = "الصراط"
    al = align_words([match], hyp("الصراط", prob=0.8), letter_refs=[shown])
    assert len(al[0].letter_scores) == 5
    assert all(s == 0.8 for s in al[0].letter_scores)
