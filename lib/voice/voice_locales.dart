/// Maps an app language code onto the locale tags a platform speech engine
/// actually understands.
///
/// The 19 AfriSLM languages are stored as bare BCP-47 codes (`lg`, `sw`,
/// `zu`, …), but `flutter_tts` and `speech_to_text` both want a region-
/// qualified tag — `sw-TZ` for TTS, `sw_TZ` for STT. Neither engine ships a
/// voice for most of these languages, so every lookup has to end in a
/// fallback rather than an exception: a Luganda student pressing "Soma
/// waggulu" must hear *something*, even if the device only has an English
/// voice to say it with. Hiding the button instead removes the feature.
library;

/// Region-qualified candidates for [code], most specific first.
///
/// Regions are the ones the language is actually spoken in, so a device that
/// carries the voice at all is likely to carry it under one of these tags.
/// The bare code is always included last — some engines register `sw` with
/// no region.
const _regions = <String, List<String>>{
  'af': ['ZA'],
  'am': ['ET'],
  'en': ['US', 'GB', 'ZA'],
  'ha': ['NG', 'NE'],
  'ig': ['NG'],
  'lg': ['UG'],
  'ln': ['CD'],
  'mg': ['MG'],
  'ny': ['MW', 'ZM'],
  'om': ['ET'],
  'rn': ['BI'],
  'rw': ['RW'],
  'sn': ['ZW'],
  'so': ['SO', 'ET', 'KE'],
  'st': ['ZA', 'LS'],
  'sw': ['KE', 'TZ', 'UG'],
  'tn': ['ZA', 'BW'],
  'wo': ['SN'],
  'xh': ['ZA'],
  'yo': ['NG'],
  'zu': ['ZA'],
};

/// TTS-style tags (`sw-KE`) for [code], best first.
List<String> ttsLocaleCandidates(String code) =>
    _candidates(code, separator: '-');

/// STT-style tags (`sw_KE`) for [code], best first.
List<String> sttLocaleCandidates(String code) =>
    _candidates(code, separator: '_');

List<String> _candidates(String code, {required String separator}) {
  final base = _baseCode(code);
  if (base.isEmpty) return const [];
  return [
    for (final region in _regions[base] ?? const <String>[])
      '$base$separator$region',
    base,
  ];
}

/// Picks the first candidate for [code] that [available] also lists.
///
/// Matching is case- and separator-insensitive because the two plugins
/// disagree on both: `flutter_tts` reports `sw-KE` on Android and `sw_KE`
/// on some Windows voices, `speech_to_text` reports `sw_KE`. Returns null
/// when the device has no voice for the language at all — the caller then
/// leaves the engine on its default rather than setting a tag that would
/// silently make `speak` a no-op.
String? resolveLocale(String code, Iterable<String> available) {
  final normalized = <String, String>{};
  for (final tag in available) {
    normalized.putIfAbsent(_normalize(tag), () => tag);
  }

  for (final candidate in _candidates(code, separator: '-')) {
    final hit = normalized[_normalize(candidate)];
    if (hit != null) return hit;
  }

  // No region we listed matched, but the engine may carry the language under
  // a region we did not think of (`sw_CD`, say). Accept any tag whose
  // language subtag is the one asked for.
  final base = _baseCode(code);
  for (final entry in normalized.entries) {
    if (entry.key == base || entry.key.startsWith('$base-')) return entry.value;
  }
  return null;
}

String _baseCode(String code) {
  final trimmed = code.trim().toLowerCase();
  if (trimmed.isEmpty) return '';
  return trimmed.split(RegExp(r'[-_]')).first;
}

String _normalize(String tag) => tag.trim().toLowerCase().replaceAll('_', '-');
