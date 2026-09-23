import 'dart:convert';

/// One compressed exchange kept for display when a chat is reopened.
///
/// Both halves are clipped at write time. This is a recall aid, not a
/// transcript — see [SessionRecall].
class RecallExchange {
  const RecallExchange({required this.question, required this.answer});

  final String question;
  final String answer;

  Map<String, Object?> toJson() => {'q': question, 'a': answer};

  static RecallExchange? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final q = raw['q'];
    final a = raw['a'];
    if (q is! String || a is! String) return null;
    if (q.trim().isEmpty && a.trim().isEmpty) return null;
    return RecallExchange(question: q, answer: a);
  }
}

/// Everything kept on disk for a single chat session.
///
/// Deliberately *not* a conversation log. CLAUDE.md's memory rule is
/// "compressed summaries only", so what is stored is:
///   - enough metadata to list and recognise the chat in the sidebar
///   - a clipped question/answer gist so a student can see what it was about
///   - the tutor's own [ConversationMemory] snapshot so reopening resumes at
///     the right stage with the right context instead of cold-starting
///
/// A full chat lands around 2-8 KB, so one small file per session is cheap to
/// write every turn and cheap to read back.
class SessionRecall {
  const SessionRecall({
    required this.id,
    required this.studentId,
    required this.title,
    required this.topic,
    required this.stage,
    required this.createdAt,
    required this.updatedAt,
    this.exchanges = const [],
    this.memory = const {},
  });

  /// Current on-disk format. Bump when the shape changes incompatibly;
  /// [fromJson] refuses anything it does not understand rather than guessing.
  static const int formatVersion = 1;

  /// Clip applied to each gist half. Matches `ConversationMemory.turnClipChars`
  /// so the display gist and the tutor's memory stay the same resolution.
  static const int clipChars = 180;

  /// Sidebar titles are the student's own words — this is the budget.
  static const int titleChars = 48;

  /// Upper bound on retained exchanges. A very long session keeps the most
  /// recent ones; the older material still survives as the memory digest.
  static const int maxExchanges = 40;

  final String id;
  final int studentId;
  final String title;
  final String topic;
  final String stage;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<RecallExchange> exchanges;

  /// Opaque `ConversationMemory.toJson()` payload.
  final Map<String, Object?> memory;

  int get turnCount => exchanges.length;

  /// Short line shown under the title in the sidebar.
  String get preview {
    for (final e in exchanges.reversed) {
      final a = e.answer.trim();
      if (a.isNotEmpty) return a;
    }
    return '';
  }

  SessionRecall copyWith({
    String? title,
    String? topic,
    String? stage,
    DateTime? updatedAt,
    List<RecallExchange>? exchanges,
    Map<String, Object?>? memory,
  }) {
    return SessionRecall(
      id: id,
      studentId: studentId,
      title: title ?? this.title,
      topic: topic ?? this.topic,
      stage: stage ?? this.stage,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      exchanges: exchanges ?? this.exchanges,
      memory: memory ?? this.memory,
    );
  }

  /// Append one exchange, clipping both halves and trimming to
  /// [maxExchanges] so the file cannot grow without bound.
  SessionRecall withExchange({
    required String question,
    required String answer,
    required String stage,
    required Map<String, Object?> memory,
    String? topic,
    DateTime? at,
  }) {
    final next = <RecallExchange>[
      ...exchanges,
      RecallExchange(
        question: clip(question, clipChars),
        answer: clip(answer, clipChars),
      ),
    ];
    if (next.length > maxExchanges) {
      next.removeRange(0, next.length - maxExchanges);
    }
    return copyWith(
      topic: topic,
      stage: stage,
      memory: memory,
      exchanges: next,
      updatedAt: at ?? DateTime.now(),
    );
  }

  Map<String, Object?> toJson() => {
        'v': formatVersion,
        'id': id,
        'studentId': studentId,
        'title': title,
        'topic': topic,
        'stage': stage,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'gist': [for (final e in exchanges) e.toJson()],
        'memory': memory,
      };

  String encode() => jsonEncode(toJson());

  /// Parse a stored file. Returns null for anything unreadable or of an
  /// unknown version — callers treat that as "this session is gone" rather
  /// than surfacing an error, since a damaged recall must never block chat.
  static SessionRecall? decode(String raw) {
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, Object?>) return null;
      return fromJson(json);
    } catch (_) {
      return null;
    }
  }

  static SessionRecall? fromJson(Map<String, Object?> json) {
    if (json['v'] != formatVersion) return null;
    final id = json['id'];
    final studentId = json['studentId'];
    if (id is! String || id.isEmpty) return null;
    if (studentId is! int) return null;

    final created = DateTime.tryParse(json['createdAt'] as String? ?? '');
    final updated = DateTime.tryParse(json['updatedAt'] as String? ?? '');
    if (created == null || updated == null) return null;

    final gist = <RecallExchange>[];
    final rawGist = json['gist'];
    if (rawGist is List) {
      for (final entry in rawGist) {
        final e = RecallExchange.fromJson(entry);
        if (e != null) gist.add(e);
      }
    }

    final memory = json['memory'];
    return SessionRecall(
      id: id,
      studentId: studentId,
      title: json['title'] as String? ?? '',
      topic: json['topic'] as String? ?? '',
      stage: json['stage'] as String? ?? 'answer',
      createdAt: created,
      updatedAt: updated,
      exchanges: gist,
      memory: memory is Map<String, Object?> ? memory : const {},
    );
  }

  /// Clip on a word boundary where one is close, so a gist line does not end
  /// mid-word. Callers still render these as a recap, never as the student's
  /// verbatim message.
  static String clip(String text, int max) {
    final t = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (t.length <= max) return t;
    final cut = t.substring(0, max);
    final space = cut.lastIndexOf(' ');
    return '${space > max * 0.6 ? cut.substring(0, space) : cut}…';
  }

  /// A sidebar title taken from the student's own first message.
  ///
  /// Never routed through the model: a title must appear the instant the
  /// first turn lands, and putting the LLM on this path is what made the site
  /// builder feel broken.
  static String titleFrom(String firstStudentMessage) {
    final t = clip(firstStudentMessage, titleChars);
    return t.isEmpty ? 'New chat' : t;
  }
}
