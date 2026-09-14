import 'dart:async';

import 'package:ai_connect_africa/ai_core/model/model_manager.dart';
import 'package:ai_connect_africa/ai_core/providers/ai_provider.dart';
import 'package:ai_connect_africa/features/settings/fetch_packages_tile.dart';
import 'package:ai_connect_africa/services/model_fetch_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

ModelInfo _ready() => const ModelInfo(
      status: ModelStatus.ready,
      path: '/hidden',
      sizeBytes: 1,
    );

ModelInfo _missing() => const ModelInfo(
      status: ModelStatus.notInstalled,
    );

class _StubFetchController extends ModelFetchController {
  _StubFetchController(super.ref, this.seed);

  final ModelFetchUiState seed;

  @override
  Future<void> refresh() async {
    state = seed;
  }

  @override
  Future<void> fetchCore() async {
    // Tests drive state via [seed]; do not hit the network.
    state = seed.copyWith(phase: ModelFetchPhase.fetching);
    await Future<void>.delayed(Duration.zero);
    state = seed;
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required ModelFetchUiState fetchState,
  AsyncValue<ModelInfo> chat = const AsyncData(
    ModelInfo(status: ModelStatus.notInstalled),
  ),
  AsyncValue<ModelInfo> translate = const AsyncData(
    ModelInfo(status: ModelStatus.notInstalled),
  ),
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        modelInfoProvider.overrideWith((ref) async {
          if (chat is AsyncLoading) return Completer<ModelInfo>().future;
          return chat.value!;
        }),
        translateModelInfoProvider.overrideWith((ref) async {
          if (translate is AsyncLoading) {
            return Completer<ModelInfo>().future;
          }
          return translate.value!;
        }),
        modelFetchControllerProvider.overrideWith(
          (ref) => _StubFetchController(ref, fetchState),
        ),
      ],
      child: const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: FetchPackagesTile())),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('offers Install Packages when workspace is not ready',
      (tester) async {
    await _pump(
      tester,
      fetchState: const ModelFetchUiState(phase: ModelFetchPhase.idle),
      chat: AsyncData(_missing()),
      translate: AsyncData(_missing()),
    );

    expect(find.text('System Core Configuration'), findsOneWidget);
    expect(find.text('Install Packages'), findsOneWidget);
    expect(find.textContaining('Fetch Models'), findsNothing);
    expect(find.textContaining('Download Models'), findsNothing);
    expect(find.textContaining('AI Models'), findsNothing);
    expect(find.textContaining('.gguf'), findsNothing);
    expect(find.textContaining('MB'), findsNothing);
  });

  testWidgets('shows Ready when packages are installed', (tester) async {
    await _pump(
      tester,
      fetchState: const ModelFetchUiState(
        phase: ModelFetchPhase.ready,
        receivedBytes: 1,
        totalBytes: 1,
        statusLabel: 'Ready',
      ),
      chat: AsyncData(_ready()),
      translate: AsyncData(_ready()),
    );

    expect(find.text('All packages installed.'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.text('Install Packages'), findsNothing);
  });

  testWidgets('progress shows narrative status without byte sizes',
      (tester) async {
    await _pump(
      tester,
      fetchState: const ModelFetchUiState(
        phase: ModelFetchPhase.fetching,
        receivedBytes: 100,
        totalBytes: 200,
        statusLabel: 'Setting up regional workspace...',
      ),
    );

    expect(find.text('Setting up regional workspace...'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
    expect(find.textContaining('656'), findsNothing);
    expect(find.textContaining('/models/'), findsNothing);
  });
}
