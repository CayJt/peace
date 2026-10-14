"""Reference verse text (words -> letters), fetched from Quran.com API v4."""
import httpx

API = "https://api.quran.com/api/v4"


class VerseNotFound(Exception):
    pass


class QuranComVerseProvider:
    def __init__(self, client: httpx.Client | None = None):
        self._client = client or httpx.Client(timeout=10)
        self._cache: dict[str, list[dict]] = {}

    def clear_cache(self) -> int:
        n = len(self._cache)
        self._cache.clear()
        return n

    def get_words(self, verse_key: str) -> list[str]:
        """The verse's Uthmani words (ayah-number marker excluded)."""
        return [w["uthmani"] for w in self.get_reference(verse_key)]

    def get_reference(self, verse_key: str) -> list[dict]:
        """Words as `{"uthmani", "imlaei"}` dicts, in order."""
        if verse_key in self._cache:
            return self._cache[verse_key]
        try:
            r = self._client.get(
                f"{API}/verses/by_key/{verse_key}",
                params={"words": "true", "word_fields": "text_uthmani,text_imlaei"},
            )
        except httpx.HTTPError as e:
            raise VerseNotFound(str(e)) from e
        if r.status_code != 200:
            raise VerseNotFound(verse_key)
        words = [
            {"uthmani": w["text_uthmani"], "imlaei": w.get("text_imlaei") or w["text_uthmani"]}
            for w in r.json()["verse"]["words"]
            if w.get("char_type_name") != "end"
        ]
        self._cache[verse_key] = words
        return words


_default = QuranComVerseProvider()


def get_verse_provider() -> QuranComVerseProvider:
    return _default
