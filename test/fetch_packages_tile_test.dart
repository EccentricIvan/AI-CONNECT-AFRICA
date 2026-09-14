import 'dart:async';

import 'package:ai_connect_africa/features/settings/fetch_packages_tile.dart';
import 'package:ai_connect_africa/services/model_fetch_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeModelFetchService extends ModelFetchService {
  _FakeModelFetchService({
    required this.coreReady,
    this.coreReadyFuture,
  });

  final bool coreReady;
  final Future<bool>? coreReadyFuture;

  @override
  Future<bool> areCorePackagesReady() => coreReadyFuture ?? Future.value(coreReady);

  @override
  Future<bool> isCoderReady() async => false;
}

Future<void> _pump(
  WidgetTester tester, {
  required _FakeModelFetchService service,
  bool settle = true,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        modelFetchServiceProvider.overrideWithValue(service),
      ],
      child: const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: FetchPackagesTile())),
      ),
    ),
  );
  if (settle) {
    await tester.pump();
  }
}

void main() {
  testWidgets('offers a Fetch action when core packages are missing',
      (tester) async {
    await _pump(
      tester,
      service: _FakeModelFetchService(coreReady: false),
    );

    expect(find.text('Fetch packages'), findsNWidgets(2));
    expect(find.widgetWithText(FilledButton, 'Fetch packages'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsNothing);
  });

  testWidgets('shows a tick instead of a button once core packages are installed',
      (tester) async {
    await _pump(
      tester,
      service: _FakeModelFetchService(coreReady: true),
    );

    expect(find.text('All packages installed.'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Fetch packages'), findsNothing);
  });

  testWidgets('keeps the tile in pre-check state while readiness is pending',
      (tester) async {
    final pending = Completer<bool>();
    await _pump(
      tester,
      service: _FakeModelFetchService(
        coreReady: false,
        coreReadyFuture: pending.future,
      ),
      settle: false,
    );

    expect(find.text('Fetch packages'), findsNWidgets(2));
    expect(find.text('All packages installed.'), findsNothing);
    expect(
      find.textContaining('Download tutor'),
      findsNothing,
    );
  });
}
