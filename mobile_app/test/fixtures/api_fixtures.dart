/// SYNTHETIC fixtures shaped like Quran.com v4 `verses/by_page` payloads.
/// They exercise our pipeline; they are NOT an authority on Quran text.
/// Authenticity is only established by running the audit against the live API.
Map<String, dynamic> _w(int id, int pos, String t, String tr) =>
    {'id': id, 'position': pos, 'text_uthmani': t, 'text_imlaei': t, 'char_type_name': 'word', 'translation': {'text': tr}};

Map<String, dynamic> _end(int id, int pos, int n) =>
    {'id': id, 'position': pos, 'text_uthmani': '$n', 'char_type_name': 'end', 'translation': {'text': '$n'}};

final Map<String, dynamic> fatihah1 = {
  'id': 1,
  'verse_number': 1,
  'verse_key': '1:1',
  'juz_number': 1,
  'page_number': 1,
  'text_uthmani': 'بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ',
  'text_imlaei': 'بسم الله الرحمن الرحيم',
  'words': [
    _w(1, 1, 'بِسْمِ', 'Dengan nama'),
    _w(2, 2, 'ٱللَّهِ', 'Allah'),
    _w(3, 3, 'ٱلرَّحْمَٰنِ', 'Maha Pengasih'),
    _w(4, 4, 'ٱلرَّحِيمِ', 'Maha Penyayang'),
    _end(5, 5, 1),
  ],
  'translations': [
    {'resource_id': 33, 'text': 'Dengan nama Allah Yang Maha Pengasih, Maha Penyayang.'}
  ],
};

final Map<String, dynamic> ikhlas1 = {
  'id': 6222,
  'verse_number': 1,
  'verse_key': '112:1',
  'juz_number': 30,
  'page_number': 604,
  'text_uthmani': 'قُلْ هُوَ ٱللَّهُ أَحَدٌ',
  'text_imlaei': 'قل هو الله أحد',
  'words': [
    _w(100, 1, 'قُلْ', 'Katakanlah'),
    _w(101, 2, 'هُوَ', 'Dialah'),
    _w(102, 3, 'ٱللَّهُ', 'Allah'),
    _w(103, 4, 'أَحَدٌ', 'Yang Maha Esa'),
    _end(104, 5, 1),
  ],
  'translations': [
    {'resource_id': 33, 'text': 'Katakanlah (Muhammad), “Dialah Allah, Yang Maha Esa.'}
  ],
};

Map<String, dynamic> pageOf(List<Map<String, dynamic>> verses) => {'verses': verses};
