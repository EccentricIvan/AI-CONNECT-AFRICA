import 'package:ai_connect_africa/ai_core/model/model_locations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  });
  tearDownAll(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('named GGUF is searched next to the exe and in Documents/OTIC', () async {
    final files = await modelCandidateFiles('qwen-0.6b-instruct.gguf');
    expect(files, isNotEmpty);
    expect(
      files.any((f) => p.basename(f) == 'qwen-0.6b-instruct.gguf'),
      isTrue,
    );
  });
}
