import 'dart:async';

import 'package:ai_connect_africa/features/teacher/teacher_pin.dart';

/// Runs before every test file: PIN hashing stays on the test's own
/// isolate, which a widget test's fake clock can wait for.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  pinHashInIsolate = false;
  await testMain();
}
