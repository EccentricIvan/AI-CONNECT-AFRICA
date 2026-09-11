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
    expect(
      m.resolveCurrent('yes'),
      contains('photosynthesis'),
    );
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
}
