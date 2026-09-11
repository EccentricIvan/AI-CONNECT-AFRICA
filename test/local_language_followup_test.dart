import 'package:flutter_test/flutter_test.dart';

import 'package:ai_connect_africa/ai_core/translate/follow_up_glossary.dart';
import 'package:ai_connect_africa/ai_core/tutor/conversation_memory.dart';
import 'package:ai_connect_africa/l10n/app_locale.dart';

void main() {
  test('glossary maps Luganda / Swahili / Kinyarwanda / Kirundi / Lingala', () {
    expect(toEnglishFollowUp('lwaki', langCode: 'lg'), 'why');
    expect(toEnglishFollowUp('kwa nini?', langCode: 'sw'), 'why');
    expect(toEnglishFollowUp('kuki', langCode: 'rw'), 'why');
    expect(toEnglishFollowUp('ego', langCode: 'rn'), 'yes');
    expect(toEnglishFollowUp('limbola lisusu', langCode: 'ln'), 'explain more');
  });

  test('English chips skip AfriSLM even in a Swahili session', () {
    expect(toEnglishFollowUp('why', langCode: 'sw'), 'why');
    expect(toEnglishFollowUp('explain more', langCode: 'lg'), 'explain more');
  });

  test('Luganda follow-up stays on the last curriculum question', () {
    final m = ConversationMemory();
    m.remember(
      student: 'What is photosynthesis?',
      tutor: 'Plants make food from sunlight.',
      verified: ['photosynthesis: plants make glucose using light, water, CO2'],
    );

    expect(m.isContinuing('lwaki'), isTrue);
    expect(m.resolveCurrent('lwaki'), contains('photosynthesis'));
    expect(m.resolveCurrent('sielewi'), contains('photosynthesis'));
  });

  test('quiz chrome exists for the six learning languages', () {
    for (final code in ['sw', 'lg', 'rw', 'rn', 'ln', 'so']) {
      expect(hasUiString(code, 'Use AI to answer this question'), isTrue);
      expect(hasUiString(code, 'Ask a follow-up about this answer...'), isTrue);
      expect(hasUiString(code, 'Why?'), isTrue);
    }
  });
}
