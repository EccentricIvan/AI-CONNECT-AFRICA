import '../../l10n/app_locale.dart';
import 'school_math.dart';

/// Nouns / method names that stay in English inside a local-language step.
/// AfriSLM still generates the surrounding sentence; these slots are restored
/// so formulas and science words are not rewritten.
const kTeachingEnglishTerms = <String>[
  'PEMDAS',
  'BODMAS',
  'fraction',
  'numerator',
  'denominator',
  'percent',
  'percentage',
  'equation',
  'perimeter',
  'area',
  'rectangle',
  'formula',
  'photosynthesis',
  'chlorophyll',
  'chloroplast',
  'chloroplasts',
  'thylakoid',
  'glucose',
  'oxygen',
  'carbon dioxide',
  'ATP',
  'NADPH',
  'Calvin',
  'mitochondria',
  'nucleus',
  'cytoplasm',
  'enzyme',
];

/// @nodoc
const kMathEnglishTerms = kTeachingEnglishTerms;

final _termPattern = RegExp(
  '\\b(${kTeachingEnglishTerms.map(RegExp.escape).join('|')})\\b',
  caseSensitive: false,
);

/// Numbers, fractions, and the variable `x` stay in English.
final _constPattern = RegExp(
  r"\d+(?:\.\d+)?(?:\s*/\s*\d+(?:\.\d+)?)?|\bx\b",
);

class ProtectedProse {
  const ProtectedProse(this.text, this.slots);

  final String text;
  final List<String> slots;

  String restore(String translated) {
    var out = translated;
    for (var i = 0; i < slots.length; i++) {
      out = out.replaceAll('⟦$i⟧', slots[i]);
      out = out.replaceAll('[[$i]]', slots[i]);
    }
    return out;
  }
}

/// Pin terms, constants, and names so AfriSLM cannot rewrite them.
ProtectedProse protectTeachingProse(String english) {
  final slots = <String>[];
  var text = english.replaceAllMapped(_constPattern, (m) {
    final i = slots.length;
    slots.add(m.group(0)!);
    return '⟦$i⟧';
  });
  text = text.replaceAllMapped(_termPattern, (m) {
    final i = slots.length;
    slots.add(m.group(0)!);
    return '⟦$i⟧';
  });
  return ProtectedProse(text, slots);
}

/// Pin terms, constants, and names so AfriSLM cannot rewrite them.
ProtectedProse protectMathProse(String english) => protectTeachingProse(english);

/// Translate step titles and "why" lines through AfriSLM. Formulas,
/// calculations, and the numeric [SchoolMathSolution.answer] stay as
/// computed — they are not canned language strings.
///
/// [onProgress] fires after the English card is ready and again after each
/// generated title/why so the student sees the systematic layout immediately.
Future<SchoolMathSolution> localizeSchoolMath(
  SchoolMathSolution math, {
  String langCode = 'en',
  required Future<String> Function(String english) translate,
  void Function(SchoolMathSolution partial)? onProgress,
}) async {
  if (langCode == 'en') {
    onProgress?.call(math);
    return math;
  }

  onProgress?.call(math);
  final cache = <String, String>{};

  Future<String> one(String english) async {
    final trimmed = english.trim();
    if (trimmed.isEmpty) return english;
    if (hasUiString(langCode, trimmed)) {
      return uiString(langCode, trimmed) ?? trimmed;
    }
    final hit = cache[trimmed];
    if (hit != null) return hit;
    final protected = protectTeachingProse(trimmed);
    final raw = (await translate(protected.text)).trim();
    final out = raw.isEmpty ? trimmed : protected.restore(raw);
    if (out.trim() != trimmed) cache[trimmed] = out;
    return out;
  }

  final steps = List<MathStep>.from(math.steps);
  for (var i = 0; i < steps.length; i++) {
    steps[i] = steps[i].copyWith(
      title: await one(steps[i].title),
      why: await one(steps[i].why),
    );
    onProgress?.call(math.copyWith(steps: List<MathStep>.from(steps)));
  }

  return math.copyWith(
    steps: steps,
    hint: await one(math.hint),
    practiceQuestion: math.practiceQuestion,
  );
}
