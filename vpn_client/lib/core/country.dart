/// Guesses an ISO 3166-1 alpha-2 country code from a server name.
///
/// Order: flag emoji, then known country names (RU/EN), then a standalone
/// two-letter code token. Returns null when nothing matches.
String? detectCountry(String name) {
  final flag = _fromFlagEmoji(name);
  if (flag != null) return flag;

  final lower = name.toLowerCase();
  for (final entry in _names.entries) {
    for (final word in entry.value) {
      if (lower.contains(word)) return entry.key;
    }
  }

  for (final token in name.split(RegExp(r'[^A-Za-z]+'))) {
    if (token.length == 2 && token == token.toUpperCase()) {
      final code = token == 'UK' ? 'GB' : token;
      if (_names.containsKey(code)) return code;
    }
  }
  return null;
}

String? _fromFlagEmoji(String s) {
  final runes = s.runes.toList();
  for (var i = 0; i + 1 < runes.length; i++) {
    final a = runes[i], b = runes[i + 1];
    if (_isRegional(a) && _isRegional(b)) {
      return String.fromCharCodes([a - 0x1F1E6 + 65, b - 0x1F1E6 + 65]);
    }
  }
  return null;
}

bool _isRegional(int r) => r >= 0x1F1E6 && r <= 0x1F1FF;

/// Russian display names for UI ("Германия").
const countryNamesRu = <String, String>{
  'RU': 'Россия', 'DE': 'Германия', 'NL': 'Нидерланды', 'FI': 'Финляндия', 'SE': 'Швеция',
  'NO': 'Норвегия', 'PL': 'Польша', 'LV': 'Латвия', 'LT': 'Литва', 'EE': 'Эстония',
  'FR': 'Франция', 'GB': 'Великобритания', 'US': 'США', 'CA': 'Канада', 'TR': 'Турция',
  'KZ': 'Казахстан', 'AM': 'Армения', 'GE': 'Грузия', 'AE': 'ОАЭ', 'JP': 'Япония',
  'SG': 'Сингапур', 'HK': 'Гонконг', 'CH': 'Швейцария', 'AT': 'Австрия', 'IT': 'Италия',
  'ES': 'Испания', 'CZ': 'Чехия', 'RO': 'Румыния', 'BG': 'Болгария', 'MD': 'Молдова',
  'UA': 'Украина', 'BY': 'Беларусь', 'IL': 'Израиль', 'IN': 'Индия', 'KR': 'Южная Корея',
  'AU': 'Австралия', 'BR': 'Бразилия', 'SK': 'Словакия', 'HU': 'Венгрия', 'RS': 'Сербия',
};

const _names = <String, List<String>>{
  'RU': ['росси', 'russia', 'москв', 'moscow', 'санкт', 'питер'],
  'DE': ['герман', 'germany', 'франкфурт', 'frankfurt', 'берлин', 'berlin'],
  'NL': ['нидерланд', 'netherlands', 'голланд', 'амстердам', 'amsterdam'],
  'FI': ['финлянд', 'finland', 'хельсинк', 'helsinki'],
  'SE': ['швеци', 'sweden', 'стокгольм', 'stockholm'],
  'NO': ['норвеги', 'norway'],
  'PL': ['польш', 'poland', 'варшав', 'warsaw'],
  'LV': ['латви', 'latvia', 'рига', 'riga'],
  'LT': ['литв', 'lithuania', 'вильнюс', 'vilnius'],
  'EE': ['эстони', 'estonia', 'таллин', 'tallinn'],
  'FR': ['франци', 'france', 'париж', 'paris'],
  'GB': ['великобритан', 'британ', 'united kingdom', 'england', 'лондон', 'london'],
  'US': ['сша', 'united states', 'america', 'нью-йорк', 'new york', 'usa'],
  'CA': ['канад', 'canada', 'торонто', 'toronto'],
  'TR': ['турци', 'turkey', 'türkiye', 'стамбул', 'istanbul'],
  'KZ': ['казахстан', 'kazakhstan', 'алмат', 'almaty', 'астана', 'astana'],
  'AM': ['армени', 'armenia', 'ереван', 'yerevan'],
  'GE': ['грузи', 'georgia', 'тбилиси', 'tbilisi'],
  'AE': ['оаэ', 'emirates', 'дубай', 'dubai'],
  'JP': ['япони', 'japan', 'токио', 'tokyo'],
  'SG': ['сингапур', 'singapore'],
  'HK': ['гонконг', 'hong kong'],
  'CH': ['швейцари', 'switzerland', 'цюрих', 'zurich'],
  'AT': ['австри', 'austria', 'вена', 'vienna'],
  'IT': ['итали', 'italy', 'милан', 'milan'],
  'ES': ['испани', 'spain', 'мадрид', 'madrid'],
  'CZ': ['чехи', 'czech', 'праг', 'prague'],
  'RO': ['румыни', 'romania'],
  'BG': ['болгари', 'bulgaria', 'софия', 'sofia'],
  'MD': ['молдов', 'moldova'],
  'UA': ['украин', 'ukraine', 'киев', 'kyiv'],
  'BY': ['беларус', 'belarus', 'минск', 'minsk'],
  'IL': ['израил', 'israel'],
  'IN': ['инди', 'india'],
  'KR': ['коре', 'korea', 'сеул', 'seoul'],
  'AU': ['австрали', 'australia', 'сидней', 'sydney'],
  'BR': ['бразили', 'brazil'],
  'SK': ['словаки', 'slovakia'],
  'HU': ['венгри', 'hungary', 'будапешт', 'budapest'],
  'RS': ['серби', 'serbia', 'белград', 'belgrade'],
};
