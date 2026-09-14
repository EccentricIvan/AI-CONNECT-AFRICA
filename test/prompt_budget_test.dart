import 'package:flutter_test/flutter_test.dart';

import 'package:ai_connect_africa/ai_core/inference/native_ffi_config.dart';
import 'package:ai_connect_africa/ai_core/inference/prompt_budget.dart';
import 'package:ai_connect_africa/ai_core/tutor/tutor_contract.dart';

void main() {
  test('fitLlamaChatBodies keeps CURRENT when clipping long THREAD', () {
    final thread = StringBuffer();
    for (var i = 0; i < 40; i++) {
      thread.writeln('Student: long prior turn number $i about photosynthesis');
      thread.writeln('Tutor: long prior answer number $i with extra detail');
    }
    final user = '${thread}CURRENT: What is chlorophyll?\nTutor:';
    final fitted = fitLlamaChatBodies(
      system: kTutorContract,
      user: user,
    );
    expect(fitted.user, contains('CURRENT: What is chlorophyll?'));
    final total =
        (fitted.system?.length ?? 0) + fitted.user.length + kLlamaTemplateOverheadChars;
    expect(total, lessThanOrEqualTo(kLlamaPrefillCharBudget));
  });

  test('prefill budget stays under llama batch with margin', () {
    // ~3 chars/token → budget tokens should be < n_batch.
    final approxTokens = kLlamaPrefillCharBudget / kLlamaCharsPerTokenBudget;
    expect(approxTokens, lessThan(kLlamaBatchSize.toDouble()));
  });

  test('oversized system is clipped before dropping CURRENT', () {
    final hugeSys = 'A' * 5000;
    final fitted = fitLlamaChatBodies(
      system: hugeSys,
      user: 'CURRENT: short question',
    );
    expect(fitted.user, contains('CURRENT: short question'));
    expect(fitted.system!.length, lessThan(hugeSys.length));
  });
}
