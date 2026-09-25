import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai_core/model/model_manager.dart' show ModelStatus;
import '../../ai_core/providers/ai_provider.dart';
import 'app_build_coder.dart';
import 'ui_schema_interpreter.dart';

enum AppBuildPhase {
  picking,
  building,
  ready,
}

class AppBuildStudioState {
  const AppBuildStudioState({
    this.phase = AppBuildPhase.picking,
    this.intent,
    this.previewHtml = '',
    this.usedCoder = false,
    this.buildNote = '',
    this.previewMode = true,
    this.error,
  });

  final AppBuildPhase phase;
  final AppBuildIntent? intent;

  /// HTML the Preview WebView / schema Source editor share.
  final String previewHtml;
  final bool usedCoder;
  final String buildNote;
  final bool previewMode;
  final String? error;

  AppBuildStudioState copyWith({
    AppBuildPhase? phase,
    AppBuildIntent? intent,
    String? previewHtml,
    bool? usedCoder,
    String? buildNote,
    bool? previewMode,
    String? error,
    bool clearError = false,
  }) {
    return AppBuildStudioState(
      phase: phase ?? this.phase,
      intent: intent ?? this.intent,
      previewHtml: previewHtml ?? this.previewHtml,
      usedCoder: usedCoder ?? this.usedCoder,
      buildNote: buildNote ?? this.buildNote,
      previewMode: previewMode ?? this.previewMode,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class AppBuildController extends Notifier<AppBuildStudioState> {
  @override
  AppBuildStudioState build() => const AppBuildStudioState();

  void reset() {
    state = const AppBuildStudioState();
  }

  void setPreviewMode(bool preview) {
    state = state.copyWith(previewMode: preview);
  }

  void applyCodeEdits(String source) {
    final trimmed = source.trim();
    if (trimmed.isEmpty) return;
    final intent = state.intent;
    final safe = (intent != null && parseUiSchema(trimmed) == null)
        ? fallbackUiSchemaSource(intent)
        : trimmed;
    state = state.copyWith(
      previewHtml: safe,
      previewMode: true,
      clearError: true,
    );
  }

  /// Locks [intent] and runs the hybrid AiCoderService → UI schema preview.
  Future<void> buildFromIntent(AppBuildIntent intent) async {
    state = state.copyWith(
      phase: AppBuildPhase.building,
      intent: intent,
      buildNote: 'Getting ready…',
      clearError: true,
    );

    final fallback = fallbackUiSchemaSource(intent);
    var schema = fallback;
    var usedCoder = false;

    try {
      final info = await ref.read(programmingModelInfoProvider.future);
      if (info.status != ModelStatus.ready) {
        state = state.copyWith(
          buildNote: 'Using the ready-made app screen.',
        );
      } else {
        state = state.copyWith(buildNote: 'Writing your app…');
        final coder = await ref.read(aiCoderServiceProvider.future);

        var lastUi = DateTime.fromMillisecondsSinceEpoch(0);
        final generated = await coder.generateAppUiSchema(
          intent: intent,
          onToken: (cumulative) {
            final now = DateTime.now();
            if (now.difference(lastUi).inMilliseconds < 400) return;
            lastUi = now;
            state = state.copyWith(
              buildNote:
                  'Writing your app… (${cumulative.length} characters)',
            );
          },
        ).timeout(
          const Duration(minutes: 3),
          onTimeout: () => null,
        );

        if (generated != null && parseUiSchema(generated) != null) {
          schema = generated;
          usedCoder = true;
        }
      }
    } catch (e, st) {
      debugPrint('AppBuildController build failed: $e\n$st');
      schema = fallback;
      usedCoder = false;
    }

    state = state.copyWith(
      phase: AppBuildPhase.ready,
      previewHtml: schema,
      usedCoder: usedCoder,
      buildNote: '',
      previewMode: true,
      clearError: true,
    );
  }
}

final appBuildControllerProvider =
    NotifierProvider<AppBuildController, AppBuildStudioState>(
  AppBuildController.new,
);
