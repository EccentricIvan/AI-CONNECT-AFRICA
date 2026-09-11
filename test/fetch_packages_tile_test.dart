import 'dart:async';

import 'package:ai_connect_africa/ai_core/model/model_manager.dart';
import 'package:ai_connect_africa/ai_core/providers/ai_provider.dart';
import 'package:ai_connect_africa/features/settings/fetch_packages_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

ModelInfo _ready() => const ModelInfo(
      status: ModelStatus.ready,
      path: '/models/x',
      sizeBytes: 600 * 1024 * 1024,
    );

ModelInfo _missing() => const ModelInfo(status: ModelStatus.notInstalled);

Future<void> _pump(
  WidgetTester tester, {
  required AsyncValue<ModelInfo> chat,
  required AsyncValue<ModelInfo> translate,
}) async {
  Override overrideWith(
    FutureProvider<ModelInfo> p,
    AsyncValue<ModelInfo> v,
  ) =>
      p.overrideWith((ref) async {
        // A pending future models the real first-launch window, where the
        // filesystem lookup has not answered yet.
        if (v is AsyncLoading) return Completer<ModelInfo>().future;
        return v.value!;
      });

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        overrideWith(modelInfoProvider, chat),
        overrideWith(translateModelInfoProvider, translate),
      ],
      child: const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: FetchPackagesTile())),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('offers a Fetch button for a model that is not installed',
      (tester) async {
    await _pump(
      tester,
      chat: AsyncData(_missing()),
      translate: AsyncData(_missing()),
    );

    expect(find.text('Fetch packages'), findsOneWidget);
    // Chat is the only fetchable package: NLLB INT8 ONNX (~1.1 GB) ships on
    // disk / USB and is never downloaded from the model-pack release.
    expect(find.widgetWithText(FilledButton, 'Fetch'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsNothing);
  });

  testWidgets('shows a tick instead of a button once a model is installed',
      (tester) async {
    await _pump(
      tester,
      chat: AsyncData(_ready()),
      translate: AsyncData(_missing()),
    );

    // The chat model is installed, so its row shows a tick and no button.
    // A missing NLLB bundle is not a fetchable package and must not put a
    // dead-end download button on this tile.
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Fetch'), findsNothing);
  });

  testWidgets('reports all packages installed when the chat model is ready',
      (tester) async {
    await _pump(
      tester,
      chat: AsyncData(_ready()),
      translate: AsyncData(_ready()),
    );

    expect(find.text('All packages installed.'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Fetch'), findsNothing);
  });

  testWidgets('does not claim models are missing while the check is pending',
      (tester) async {
    await _pump(
      tester,
      chat: const AsyncLoading(),
      translate: const AsyncLoading(),
    );

    // The regression this guards: treating an unresolved filesystem lookup
    // as "missing" flashed the download prompt on a device that already had
    // both models.
    expect(find.text('All packages installed.'), findsOneWidget);
    expect(
      find.textContaining('Download tutor'),
      findsNothing,
      reason: 'a pending lookup must not render as a missing model',
    );
  });
}
