import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What a student had on screen in one coding section.
///
/// Held above the route so leaving a lab — to ask the tutor something, to
/// check a lesson — and coming back does not throw the work away. A student
/// on a shared school device may be interrupted constantly; losing a page of
/// typed code to a mis-tap is the difference between finishing a project and
/// abandoning it.
class CodeLabSession {
  const CodeLabSession({
    this.code = '',
    this.lessonIndex = 0,
    this.result = '',
    this.tab = 0,
    this.hasRun = false,
  });

  /// Exactly what is in the editor.
  final String code;

  final int lessonIndex;

  /// The rendered side: preview HTML for the web/app labs, simulator output
  /// for Python. Kept so returning lands on the finished page, not a blank one.
  final String result;

  /// 0 = code, 1 = preview/output.
  final int tab;

  final bool hasRun;

  CodeLabSession copyWith({
    String? code,
    int? lessonIndex,
    String? result,
    int? tab,
    bool? hasRun,
  }) {
    return CodeLabSession(
      code: code ?? this.code,
      lessonIndex: lessonIndex ?? this.lessonIndex,
      result: result ?? this.result,
      tab: tab ?? this.tab,
      hasRun: hasRun ?? this.hasRun,
    );
  }

  bool get isEmpty => code.trim().isEmpty;
}

/// Every coding section's saved session, keyed by section id.
///
/// Deliberately in memory only: a device is shared between students, so one
/// learner's half-finished code must not reappear for the next person after a
/// restart. It survives navigation, not the app closing.
class CodeLabSessionStore extends Notifier<Map<String, CodeLabSession>> {
  @override
  Map<String, CodeLabSession> build() => const {};

  CodeLabSession? read(String sectionId) => state[sectionId];

  void save(String sectionId, CodeLabSession session) {
    state = {...state, sectionId: session};
  }

  /// Merges one field set into the saved session, creating it if absent.
  void update(
    String sectionId, {
    String? code,
    int? lessonIndex,
    String? result,
    int? tab,
    bool? hasRun,
  }) {
    final current = state[sectionId] ?? const CodeLabSession();
    save(
      sectionId,
      current.copyWith(
        code: code,
        lessonIndex: lessonIndex,
        result: result,
        tab: tab,
        hasRun: hasRun,
      ),
    );
  }

  /// Drops one section's work — the "start over" path.
  void clear(String sectionId) {
    final next = {...state}..remove(sectionId);
    state = next;
  }
}

final codeLabSessionProvider =
    NotifierProvider<CodeLabSessionStore, Map<String, CodeLabSession>>(
  CodeLabSessionStore.new,
);

/// Section ids. Constants rather than raw strings so a typo cannot silently
/// hand one lab another lab's saved code.
class CodeLabSections {
  const CodeLabSections._();

  static const web = 'weblab';
  static const app = 'applab';
  static const python = 'pythonlab';
}
