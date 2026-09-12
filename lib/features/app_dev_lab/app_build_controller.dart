import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai_core/model/model_manager.dart' show ModelStatus;
import '../../ai_core/providers/ai_provider.dart';
import 'app_build_coder.dart';

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

  /// HTML the Preview WebView and Code editor share (what the coder wrote).
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
    state = state.copyWith(
      previewHtml: trimmed,
      previewMode: true,
      clearError: true,
    );
  }

  /// Locks [intent] and runs Qwen 1.5B Coder → HTML preview (website-style).
  Future<void> buildFromIntent(AppBuildIntent intent) async {
    state = state.copyWith(
      phase: AppBuildPhase.building,
      intent: intent,
      buildNote: 'Loading coding model…',
      clearError: true,
    );

    final fallback = fallbackAppHtml(intent);
    var html = fallback;
    var usedCoder = false;

    try {
      final info = await ref.read(programmingModelInfoProvider.future);
      if (info.status != ModelStatus.ready) {
        state = state.copyWith(
          buildNote: 'Coding model not found — using offline app shell.',
        );
      } else {
        state = state.copyWith(buildNote: 'Coding model writing your app…');
        final engine = await ref.read(programmingEngineProvider.future);

        var lastUi = DateTime.fromMillisecondsSinceEpoch(0);
        final generated = await generateAppHtmlWithCoder(
          engine: engine,
          intent: intent,
          onToken: (cumulative) {
            final now = DateTime.now();
            if (now.difference(lastUi).inMilliseconds < 400) return;
            lastUi = now;
            state = state.copyWith(
              buildNote:
                  'Coding model writing your app… (${cumulative.length} chars)',
            );
          },
        ).timeout(
          const Duration(minutes: 3),
          onTimeout: () => null,
        );

        if (generated != null && generated.trim().length > 200) {
          html = generated;
          usedCoder = true;
        }
      }
    } catch (e, st) {
      debugPrint('AppBuildController build failed: $e\n$st');
      html = fallback;
      usedCoder = false;
    }

    state = state.copyWith(
      phase: AppBuildPhase.ready,
      previewHtml: html,
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
