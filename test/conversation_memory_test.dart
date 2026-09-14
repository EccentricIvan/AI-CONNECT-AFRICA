import 'package:flutter_test/flutter_test.dart';

import 'package:ai_connect_africa/ai_core/tutor/conversation_memory.dart';

void main() {
  test('yes continues the last real question, not a new topic', () {
    final m = ConversationMemory();
    m.remember(
      student: 'What is photosynthesis?',
      tutor: 'Plants make food from sunlight.',
      verified: ['photosynthesis: plants make glucose using light, water, CO2'],
    );

    expect(m.isContinuing('yes'), isTrue);
    expect(m.resolveCurrent('yes'), contains('photosynthesis'));
    expect(m.resolveCurrent('yes'), isNot(equals('yes')));
  });

  test('THREAD keeps both sides of the last exchange', () {
    final m = ConversationMemory();
    m.remember(
      student: 'What is photosynthesis?',
      tutor: 'Plants make food from sunlight and carbon dioxide.',
    );
    final block = m.promptBlock();
    expect(block, contains('Student: What is photosynthesis?'));
    expect(block, contains('Tutor: Plants make food'));
  });

  test('only verified facts are ESTABLISHED', () {
    final m = ConversationMemory();
    m.remember(
      student: 'Explain cells',
      tutor: 'Cells are made of cheese.',
      verified: ['cell: the basic unit of life'],
    );
    expect(m.established, ['cell: the basic unit of life']);
    expect(m.promptBlock(), contains('ESTABLISHED'));
  });

  test('a correction drops the newest established fact', () {
    final m = ConversationMemory();
    m.remember(
      student: 'What is DNA?',
      tutor: 'A recipe in the cell.',
      verified: ['DNA: genetic material'],
    );
    expect(m.isCorrection("that's wrong"), isTrue);
    m.noteCorrection();
    expect(m.established, isEmpty);
  });

  test('why stays anchored to the last question', () {
    final m = ConversationMemory();
    m.remember(student: 'Why do we have seasons?', tutor: 'Earth tilts.');
    expect(m.resolveCurrent('why'), contains('seasons'));
  });

  test('older exchanges fold into DIGEST instead of vanishing', () {
    final m = ConversationMemory();
    m.remember(student: 'What is a cell?', tutor: 'Basic unit of life.');
    m.remember(student: 'What is DNA?', tutor: 'Genetic material.');
    m.remember(student: 'What is a gene?', tutor: 'A DNA segment that codes for a trait.');
    expect(m.turns.length, 4);
    expect(m.lessonDigest, isNotNull);
    expect(m.lessonDigest, contains('cell'));
    final block = m.promptBlock();
    expect(block, contains('DIGEST:'));
    expect(block, contains('gene'));
    expect(block, contains('DNA'));
  });

  test('transient tutor failures are not remembered', () {
    final m = ConversationMemory();
    final ok = m.remember(
      student: 'What is gravity?',
      tutor:
          'I hit a brief snag finishing that answer. Please ask again in one short sentence.',
    );
    expect(ok, isFalse);
    expect(m.isEmpty, isTrue);
  });

  test('promptBlock respects maxChars without throwing', () {
    final m = ConversationMemory();
    for (var i = 0; i < 3; i++) {
      m.remember(
        student: 'Question number $i about ecosystems and food webs in detail?',
        tutor:
            'Answer number $i explains producers consumers and decomposers with local examples.',
        verified: ['ecosystem: living and non-living parts interacting $i'],
      );
    }
    final tight = m.promptBlock(maxChars: 180);
    expect(tight.length, lessThanOrEqualTo(180));
    expect(() => m.promptBlock(maxChars: 40), returnsNormally);
  });

  test('duplicate facts collapse to the newest wording', () {
    final m = ConversationMemory();
    m.remember(
      student: 'What is a cell?',
      tutor: 'Unit of life.',
      verified: ['cell: basic unit'],
    );
    m.remember(
      student: 'Say more about cells',
      tutor: 'They make tissues.',
      verified: ['cell: the basic unit of life'],
    );
    expect(m.established.where((e) => e.toLowerCase().startsWith('cell:')),
        hasLength(1));
    expect(m.established.last, contains('basic unit of life'));
  });

  test('anchor survives follow-up chips', () {
    final m = ConversationMemory();
    m.remember(
      student: 'What is photosynthesis?',
      tutor: 'Plants make food from light.',
    );
    m.remember(student: 'why', tutor: 'Chlorophyll captures light energy.');
    expect(m.anchorQuestion, contains('photosynthesis'));
    expect(m.resolveCurrent('more'), contains('photosynthesis'));
  });
}
