"""Arabic letter decomposition shared (by contract) with the Flutter client.

A "letter" is a base Arabic letter; harakat, shadda, sukun, Quranic annotation
marks and tatweel are attached marks and are not letters.
"""

_MARK_RANGES = ((0x064B, 0x065F), (0x0670, 0x0670), (0x06D6, 0x06ED), (0x0610, 0x061A))


def _is_mark(ch: str) -> bool:
    cp = ord(ch)
    return any(lo <= cp <= hi for lo, hi in _MARK_RANGES) or cp == 0x0640


def is_letter(ch: str) -> bool:
    cp = ord(ch)
    return (0x0621 <= cp <= 0x064A or 0x0671 <= cp <= 0x06D3) and not _is_mark(ch)


def letters_of(word: str) -> list[str]:
    return [c for c in word if is_letter(c)]
