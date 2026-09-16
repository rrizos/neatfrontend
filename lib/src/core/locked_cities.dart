/// Feature flag for the Locked Cities system.
///
/// Set to false to instantly revert to the pre-lock state everywhere:
/// all cities show green pins, feeds are open, no lock UI is shown.
const kLockedCitiesEnabled = true;

/// Cities that are always open regardless of server lock data.
const kUnlockedCities = {'Αθήνα', 'Θεσσαλονίκη'};

/// Greek demonyms (masculine form used as the generic).
/// Used in the locked-city card button: "Συνδέσου ως {demonym}".
const kCityDemonyms = <String, String>{
  'Αθήνα': 'Αθηναίος',
  'Θεσσαλονίκη': 'Θεσσαλονικέας',
  'Πάτρα': 'Πατρινός',
  'Ηράκλειο': 'Ηρακλειώτης',
  'Λάρισα': 'Λαρισαίος',
  'Βόλος': 'Βολιώτης',
  'Ιωάννινα': 'Γιαννιώτης',
  'Χαλκίδα': 'Χαλκιδαίος',
  'Καβάλα': 'Καβαλιώτης',
  'Καλαμάτα': 'Καλαματιανός',
  'Σέρρες': 'Σερραίος',
  'Αλεξανδρούπολη': 'Αλεξανδρουπολίτης',
  'Κατερίνη': 'Κατερινιώτης',
  'Τρίκαλα': 'Τρικαλινός',
  'Λαμία': 'Λαμιώτης',
  'Κομοτηνή': 'Κομοτηναίος',
  'Ξάνθη': 'Ξανθιώτης',
  'Βέροια': 'Βεροιώτης',
  'Κοζάνη': 'Κοζανίτης',
  'Αγρίνιο': 'Αγρινιώτης',
  'Δράμα': 'Δραμινός',
  'Τρίπολη': 'Τριπολίτης',
  'Κόρινθος': 'Κορίνθιος',
  'Χανιά': 'Χανιώτης',
  'Ρόδος': 'Ροδίτης',
  'Κέρκυρα': 'Κερκυραίος',
  'Μύκονος': 'Μυκονιάτης',
  'Σαντορίνη': 'Σαντορινιός',
  'Ρέθυμνο': 'Ρεθεμνιώτης',
  'Λέσβος': 'Λεσβίτης',
  'Ζάκυνθος': 'Ζακυνθινός',
  'Κεφαλονιά': 'Κεφαλονίτης',
  'Κως': 'Κώος',
  'Χίος': 'Χιώτης',
  'Σάμος': 'Σαμιώτης',
  'Σύρος': 'Συριανός',
  'Νάξος': 'Ναξιώτης',
  'Πάρος': 'Παριανός',
  'Μήλος': 'Μηλίτης',
  'Αίγινα': 'Αιγινήτης',
  'Ναύπλιο': 'Ναυπλιώτης',
  'Σπάρτη': 'Σπαρτιάτης',
  'Άργος': 'Αργείος',
  'Πύργος': 'Πυργιώτης',
  'Αίγιο': 'Αιγιώτης',
  'Ναύπακτος': 'Ναυπάκτιος',
  'Μεσολόγγι': 'Μεσολογγίτης',
  'Καρδίτσα': 'Καρδιτσιώτης',
  'Λιβαδειά': 'Λιβαδεώτης',
  'Θήβα': 'Θηβαίος',
  'Λευκάδα': 'Λευκαδίτης',
  'Πρέβεζα': 'Πρεβεζάνος',
  'Άρτα': 'Αρτινός',
  'Καστοριά': 'Καστοριανός',
  'Φλώρινα': 'Φλωρινιώτης',
  'Πτολεμαΐδα': 'Πτολεμαιτιώτης',
  'Έδεσσα': 'Εδεσσαίος',
  'Νάουσα': 'Ναουσαίος',
  'Κιλκίς': 'Κιλκισιώτης',
};

/// Returns the demonym for [cityName], falling back to the city name itself.
String demonymForCity(String cityName) =>
    kCityDemonyms[cityName] ?? cityName;

/// Genitive forms with article for use in phrases like "Το feed [genitive]".
const kCityGenitive = <String, String>{
  'Αθήνα': 'της Αθήνας',
  'Θεσσαλονίκη': 'της Θεσσαλονίκης',
  'Πάτρα': 'της Πάτρας',
  'Ηράκλειο': 'του Ηρακλείου',
  'Λάρισα': 'της Λάρισας',
  'Βόλος': 'του Βόλου',
  'Ιωάννινα': 'των Ιωαννίνων',
  'Χαλκίδα': 'της Χαλκίδας',
  'Καβάλα': 'της Καβάλας',
  'Καλαμάτα': 'της Καλαμάτας',
  'Σέρρες': 'των Σερρών',
  'Αλεξανδρούπολη': 'της Αλεξανδρούπολης',
  'Κατερίνη': 'της Κατερίνης',
  'Τρίκαλα': 'των Τρικάλων',
  'Λαμία': 'της Λαμίας',
  'Κομοτηνή': 'της Κομοτηνής',
  'Ξάνθη': 'της Ξάνθης',
  'Βέροια': 'της Βέροιας',
  'Κοζάνη': 'της Κοζάνης',
  'Αγρίνιο': 'του Αγρινίου',
  'Δράμα': 'της Δράμας',
  'Τρίπολη': 'της Τρίπολης',
  'Κόρινθος': 'της Κορίνθου',
  'Χανιά': 'των Χανίων',
  'Ρόδος': 'της Ρόδου',
  'Κέρκυρα': 'της Κέρκυρας',
  'Ρέθυμνο': 'του Ρεθύμνου',
  'Λέσβος': 'της Λέσβου',
  'Ζάκυνθος': 'της Ζακύνθου',
  'Κεφαλονιά': 'της Κεφαλονιάς',
  'Χίος': 'της Χίου',
  'Σάμος': 'της Σάμου',
  'Ναύπλιο': 'του Ναυπλίου',
  'Σπάρτη': 'της Σπάρτης',
  'Καστοριά': 'της Καστοριάς',
  'Φλώρινα': 'της Φλώρινας',
  'Πτολεμαΐδα': 'της Πτολεμαΐδας',
  'Έδεσσα': 'της Έδεσσας',
  'Νάουσα': 'της Νάουσας',
  'Κιλκίς': 'του Κιλκίς',
  'Λευκάδα': 'της Λευκάδας',
  'Πρέβεζα': 'της Πρέβεζας',
  'Άρτα': 'της Άρτας',
  'Καρδίτσα': 'της Καρδίτσας',
  'Λιβαδειά': 'της Λιβαδειάς',
  'Θήβα': 'της Θήβας',
  'Μεσολόγγι': 'του Μεσολογγίου',
  'Ναύπακτος': 'της Ναυπάκτου',
  'Μύκονος': 'της Μυκόνου',
  'Σαντορίνη': 'της Σαντορίνης',
  'Κως': 'της Κω',
  'Σύρος': 'της Σύρου',
  'Νάξος': 'της Νάξου',
  'Πάρος': 'της Πάρου',
  'Μήλος': 'της Μήλου',
  'Αίγινα': 'της Αίγινας',
  'Πύργος': 'του Πύργου',
  'Αίγιο': 'του Αιγίου',
  'Άργος': 'του Άργους',
};

/// Accusative forms for use after "από".
/// Masculine -ος cities drop the -ς; neuter/feminine cities are unchanged.
const kCityAccusative = <String, String>{
  'Βόλος': 'Βόλο',
  'Ρόδος': 'Ρόδο',
  'Κόρινθος': 'Κόρινθο',
  'Λέσβος': 'Λέσβο',
  'Ζάκυνθος': 'Ζάκυνθο',
  'Χίος': 'Χίο',
  'Σάμος': 'Σάμο',
  'Μήλος': 'Μήλο',
  'Πύργος': 'Πύργο',
  'Σύρος': 'Σύρο',
  'Νάξος': 'Νάξο',
  'Πάρος': 'Πάρο',
  'Μύκονος': 'Μύκονο',
  'Ναύπακτος': 'Ναύπακτο',
  'Κιλκίς': 'Κιλκίς',   // indeclinable
  'Κως': 'Κω',
  'Άργος': 'Άργος',      // neuter, unchanged
};

/// Locative prepositional phrases for use after "Μετακόμισε".
/// σε + article + accusative: "στην Αθήνα", "στον Βόλο", "στα Τρίκαλα", etc.
const kCityLocative = <String, String>{
  'Αθήνα':           'στην Αθήνα',
  'Θεσσαλονίκη':    'στη Θεσσαλονίκη',
  'Πάτρα':          'στην Πάτρα',
  'Ηράκλειο':       'στο Ηράκλειο',
  'Λάρισα':         'στη Λάρισα',
  'Βόλος':          'στον Βόλο',
  'Ιωάννινα':       'στα Ιωάννινα',
  'Χαλκίδα':        'στη Χαλκίδα',
  'Καβάλα':         'στην Καβάλα',
  'Καλαμάτα':       'στην Καλαμάτα',
  'Σέρρες':         'στις Σέρρες',
  'Αλεξανδρούπολη': 'στην Αλεξανδρούπολη',
  'Κατερίνη':       'στην Κατερίνη',
  'Τρίκαλα':        'στα Τρίκαλα',
  'Λαμία':          'στη Λαμία',
  'Κομοτηνή':       'στην Κομοτηνή',
  'Ξάνθη':          'στην Ξάνθη',
  'Βέροια':         'στη Βέροια',
  'Κοζάνη':         'στην Κοζάνη',
  'Αγρίνιο':        'στο Αγρίνιο',
  'Δράμα':          'στη Δράμα',
  'Τρίπολη':        'στην Τρίπολη',
  'Κόρινθος':       'στην Κόρινθο',
  'Χανιά':          'στα Χανιά',
  'Ρόδος':          'στη Ρόδο',
  'Κέρκυρα':        'στην Κέρκυρα',
  'Μύκονος':        'στη Μύκονο',
  'Σαντορίνη':      'στη Σαντορίνη',
  'Ρέθυμνο':        'στο Ρέθυμνο',
  'Λέσβος':         'στη Λέσβο',
  'Ζάκυνθος':       'στη Ζάκυνθο',
  'Κεφαλονιά':      'στην Κεφαλονιά',
  'Κως':            'στην Κω',
  'Χίος':           'στη Χίο',
  'Σάμος':          'στη Σάμο',
  'Σύρος':          'στη Σύρο',
  'Νάξος':          'στη Νάξο',
  'Πάρος':          'στην Πάρο',
  'Μήλος':          'στη Μήλο',
  'Αίγινα':         'στην Αίγινα',
  'Ναύπλιο':        'στο Ναύπλιο',
  'Σπάρτη':         'στη Σπάρτη',
  'Άργος':          'στο Άργος',
  'Πύργος':         'στον Πύργο',
  'Αίγιο':          'στο Αίγιο',
  'Ναύπακτος':      'στη Ναύπακτο',
  'Μεσολόγγι':      'στο Μεσολόγγι',
  'Καρδίτσα':       'στην Καρδίτσα',
  'Λιβαδειά':       'στη Λιβαδειά',
  'Θήβα':           'στη Θήβα',
  'Λευκάδα':        'στη Λευκάδα',
  'Πρέβεζα':        'στην Πρέβεζα',
  'Άρτα':           'στην Άρτα',
  'Καστοριά':       'στην Καστοριά',
  'Φλώρινα':        'στη Φλώρινα',
  'Πτολεμαΐδα':     'στην Πτολεμαΐδα',
  'Έδεσσα':         'στην Έδεσσα',
  'Νάουσα':         'στη Νάουσα',
  'Κιλκίς':         'στο Κιλκίς',
};

/// Returns the locative prepositional phrase for a city (for use after "Μετακόμισε").
/// e.g. "Βόλος" → "στον Βόλο", "Αθήνα" → "στην Αθήνα"
String cityLocative(String city) => kCityLocative[city] ?? city;

/// Returns the genitive phrase (article + genitive) for a city.
/// e.g. "Βόλος" → "του Βόλου", "Πάτρα" → "της Πάτρας"
String cityGenitive(String city) => kCityGenitive[city] ?? city;

/// Returns the accusative form of a city name (for use after "από").
/// e.g. "Βόλος" → "Βόλο", "Πάτρα" → "Πάτρα" (unchanged)
String cityAccusative(String city) {
  if (kCityAccusative.containsKey(city)) return kCityAccusative[city]!;
  // Masculine -ος: drop the final -ς → -ο
  if (city.endsWith('ος') || city.endsWith('ός')) {
    return city.substring(0, city.length - 1);
  }
  return city;
}

/// A latin, URL-safe form of a city name, for the `?city=` of an invite link.
///
/// Which transliteration scheme this is does not matter — nothing reads the
/// slug back as Greek, and no one types it. What matters is that the copy of
/// this function in netlify/edge-functions/invite.js produces the same string
/// for the same city: that is how the invite page turns `?city=patra` back
/// into Πάτρα and its live counter. Change one and you must change the other.
///
/// A slug the page cannot match is not a failure — the invite page falls back
/// to its city-less copy — so the two only have to agree, not be correct.
String citySlug(String city) {
  const accents = <String, String>{
    'ά': 'α', 'έ': 'ε', 'ή': 'η', 'ί': 'ι', 'ό': 'ο', 'ύ': 'υ', 'ώ': 'ω',
    'ϊ': 'ι', 'ϋ': 'υ', 'ΐ': 'ι', 'ΰ': 'υ',
  };
  const digraphs = <String, String>{'ου': 'ou', 'αυ': 'av', 'ευ': 'ev'};
  const letters = <String, String>{
    'α': 'a', 'β': 'v', 'γ': 'g', 'δ': 'd', 'ε': 'e', 'ζ': 'z', 'η': 'i',
    'θ': 'th', 'ι': 'i', 'κ': 'k', 'λ': 'l', 'μ': 'm', 'ν': 'n', 'ξ': 'x',
    'ο': 'o', 'π': 'p', 'ρ': 'r', 'σ': 's', 'ς': 's', 'τ': 't', 'υ': 'y',
    'φ': 'f', 'χ': 'ch', 'ψ': 'ps', 'ω': 'o',
  };

  // Accents come off first, so that the digraph pass still recognises the
  // "ευ" inside Λευκάδα when it arrives written as "εύ".
  final plain = StringBuffer();
  for (final ch in city.toLowerCase().split('')) {
    plain.write(accents[ch] ?? ch);
  }
  final source = plain.toString();

  final out = StringBuffer();
  for (var i = 0; i < source.length; i++) {
    final pair = i + 1 < source.length ? source.substring(i, i + 2) : '';
    final digraph = digraphs[pair];
    if (digraph != null) {
      out.write(digraph);
      i++;
      continue;
    }
    final ch = source[i];
    final letter = letters[ch];
    if (letter != null) {
      out.write(letter);
    } else if (RegExp(r'[a-z0-9]').hasMatch(ch)) {
      out.write(ch);
    } else {
      out.write('-');
    }
  }

  return out
      .toString()
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
}

/// Returns true when [cityName] should be treated as locked given [locks].
///
/// Logic:
/// • Feature off → always false.
/// • Always-open cities → always false.
/// • City has a CityConfig row with is_locked=false → false (explicitly unlocked).
/// • City has a CityConfig row with is_locked=true  → true.
/// • No row AND feature is on AND city not in always-open set → true (default).
bool isCityLocked(String cityName, Map<String, CityLockInfo> locks) {
  if (!kLockedCitiesEnabled) return false;
  if (kUnlockedCities.contains(cityName)) return false;
  final info = locks[cityName];
  if (info != null) return info.isLocked;
  // No row from server: treat as locked by default.
  return true;
}

/// Lock state for one city, as returned by /api/posts/city-locks/.
class CityLockInfo {
  const CityLockInfo({
    required this.isLocked,
    required this.threshold,
    required this.memberCount,
  });

  final bool isLocked;
  final int threshold;
  final int memberCount;

  /// Progress fraction 0.0–1.0.
  double get progress =>
      threshold > 0 ? (memberCount / threshold).clamp(0.0, 1.0) : 0.0;

  factory CityLockInfo.fromJson(Map<String, dynamic> json) => CityLockInfo(
    isLocked: json['locked'] == true,
    threshold: (json['threshold'] as num?)?.toInt() ?? 50,
    memberCount: (json['memberCount'] as num?)?.toInt() ?? 0,
  );
}
