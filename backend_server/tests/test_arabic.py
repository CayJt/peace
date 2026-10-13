from services.arabic import letters_of


def test_marks_are_not_letters():
    assert letters_of("بِسْمِ") == list("بسم")
    assert len(letters_of("ٱلرَّحْمَٰنِ")) == 6  # ا ل ر ح م ن
