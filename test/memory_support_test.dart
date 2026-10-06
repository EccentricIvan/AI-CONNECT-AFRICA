import 'package:ai_connect_africa/ai_core/inference/memory_support.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a 4 GB phone and an 8 GB computer run the AI; less does not', () {
    expect(memoryIsEnough(3.6, phone: true), isTrue);
    expect(memoryIsEnough(1.8, phone: true), isFalse);
    expect(memoryIsEnough(7.8, phone: false), isTrue);
    expect(memoryIsEnough(3.9, phone: false), isFalse);
  });

  test('an unreadable amount never takes the AI away', () {
    expect(memoryIsEnough(null, phone: true), isTrue);
  });

  test('this machine’s memory can be read', () {
    expect(deviceMemoryGb, anyOf(isNull, greaterThan(0.5)));
  });
}
