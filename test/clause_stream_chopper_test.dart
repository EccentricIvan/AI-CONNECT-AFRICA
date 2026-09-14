import 'package:ai_connect_africa/services/clause_stream_chopper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('flushes on sentence end', () {
    final flushes = <String>[];
    final c = ClauseStreamChopper(onFlush: flushes.add);
    c.add('Hello world');
    expect(flushes, isEmpty);
    c.add('. More');
    expect(flushes, isNotEmpty);
    expect(flushes.last, contains('Hello world.'));
  });

  test('flushes at 60 characters', () {
    final flushes = <String>[];
    final c = ClauseStreamChopper(flushChars: 60, onFlush: flushes.add);
    c.add('a' * 59);
    expect(flushes, isEmpty);
    c.add('b');
    expect(flushes, isNotEmpty);
    expect(flushes.last.length, 60);
  });

  test('end flushes remainder', () {
    final flushes = <String>[];
    final c = ClauseStreamChopper(onFlush: flushes.add);
    c.add('partial');
    c.end();
    expect(flushes.last, 'partial');
  });
}
