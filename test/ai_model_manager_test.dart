import 'package:ai_connect_africa/services/ai_model_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() async {
    await AiModelManager.instance.resetForTests();
  });

  test('ActiveModelMode exposes none, chatBrain, appCoder', () {
    expect(ActiveModelMode.values, containsAll([
      ActiveModelMode.none,
      ActiveModelMode.chatBrain,
      ActiveModelMode.appCoder,
    ]));
  });

  test('prepareModelForMode is a no-op off Android (Platform.isAndroid)', () async {
    final manager = AiModelManager.instance;
    await manager.resetForTests();

    // Hosted flutter_test on Windows/Linux must never enter the LiteRT swap.
    if (manager.isAndroidLiteRtHost) {
      await manager.prepareModelForMode(ActiveModelMode.chatBrain);
      return;
    }

    await manager.prepareModelForMode(ActiveModelMode.chatBrain);
    expect(manager.activeMode, ActiveModelMode.none);

    await manager.prepareModelForMode(ActiveModelMode.appCoder);
    expect(manager.activeMode, ActiveModelMode.none);
    expect(manager.chatEngine, isNull);
    expect(manager.coderEngine, isNull);
  });

  test('scheduleLiteRtMode does not throw on desktop', () {
    expect(
      () => scheduleLiteRtMode(ActiveModelMode.appCoder),
      returnsNormally,
    );
  });
}
