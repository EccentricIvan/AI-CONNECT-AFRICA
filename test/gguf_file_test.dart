import 'package:ai_connect_africa/ai_core/model/gguf_file.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('GGUF magic is the four ASCII bytes GGUF', () {
    expect(hasGgufMagic([0x47, 0x47, 0x55, 0x46]), isTrue);
    expect(hasGgufMagic('GGUF'.codeUnits), isTrue);
  });

  test('HTML and JSON downloads are not treated as GGUF', () {
    expect(hasGgufMagic('<!DOCTYPE html>'.codeUnits), isFalse);
    expect(hasGgufMagic('{'.codeUnits), isFalse);
    expect(hasGgufMagic(<int>[]), isFalse);
    expect(hasGgufMagic([0x47, 0x47, 0x55]), isFalse);
  });
}
