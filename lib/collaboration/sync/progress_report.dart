import 'dart:convert';

import 'package:drift/drift.dart';

import '../../db/otic_database.dart';

/// One learner's progress as their device reports it to the teacher.
///
/// Compressed summaries only (CLAUDE.md → Student Memory Engine): totals,
/// per-topic mastery, strengths and weaknesses. Never chats, answers or
/// anything the learner typed. Small and bounded — a report is a few KB
/// however long the learner has used the app.
class ProgressReport {
  const ProgressReport({
    required this.memberKey,
    required this.name,
    required this.points,
    required this.streakDays,
    required this.lessonsCompleted,
    required this.practiceAttempted,
    required this.practiceCorrect,
    required this.scenariosCompleted,
    required this.lastActive,
    required this.topics,
    required this.strengths,
    required this.weaknesses,
    this.enrolled = const [],
  });

  /// Subject ids the learner says they take (a record, not a lock).
  final List<String> enrolled;
  static const maxEnrolled = 30;

  final String memberKey;
  final String name;
  final int points;
  final int streakDays;
  final int lessonsCompleted;
  final int practiceAttempted;
  final int practiceCorrect;
  final int scenariosCompleted;

  /// ISO-8601 UTC, the learner device's clock (may be wrong).
  final String? lastActive;

  /// Most recently studied topics first, mastery 0–100.
  final List<({String topic, int level})> topics;
  final List<String> strengths;
  final List<String> weaknesses;

  static const maxTopics = 20;
  static const _maxList = 5;
  static const _maxText = 80;

  /// Mean mastery over [topics], or null with none.
  int? get meanLevel => topics.isEmpty
      ? null
      : (topics.map((t) => t.level).reduce((a, b) => a + b) / topics.length)
            .round();

  Map<String, Object?> toJson() => {
    'member': memberKey,
    'name': name,
    'points': points,
    'streak': streakDays,
    'lessons': lessonsCompleted,
    'practice': practiceAttempted,
    'correct': practiceCorrect,
    'scenarios': scenariosCompleted,
    'last_active': lastActive,
    'topics': [
      for (final t in topics) {'t': t.topic, 'l': t.level},
    ],
    'strengths': strengths,
    'weaknesses': weaknesses,
    'enrolled': enrolled,
  };

  /// Reads a report from another device. Null when it isn't one. Every
  /// field is clipped, so a buggy or hostile device can't bloat the
  /// teacher's database.
  static ProgressReport? fromJson(Object? json) {
    if (json is! Map) return null;
    final member = json['member'], name = json['name'];
    if (member is! String || member.isEmpty || member.length > 120) {
      return null;
    }
    if (name is! String || name.trim().isEmpty) return null;
    int n(Object? v) => v is int && v >= 0 ? v : 0;
    List<String> strings(Object? v) => [
      if (v is List)
        for (final s in v.take(_maxList))
          if (s is String && s.trim().isNotEmpty) _clip(s.trim()),
    ];
    final topics = <({String topic, int level})>[];
    final rawTopics = json['topics'];
    if (rawTopics is List) {
      for (final t in rawTopics.take(maxTopics)) {
        if (t is Map && t['t'] is String && t['l'] is int) {
          topics.add((
            topic: _clip(t['t'] as String),
            level: (t['l'] as int).clamp(0, 100),
          ));
        }
      }
    }
    final last = json['last_active'];
    return ProgressReport(
      memberKey: member,
      name: _clip(name.trim()),
      points: n(json['points']),
      streakDays: n(json['streak']),
      lessonsCompleted: n(json['lessons']),
      practiceAttempted: n(json['practice']),
      practiceCorrect: n(json['correct']),
      scenariosCompleted: n(json['scenarios']),
      lastActive: last is String && last.length <= 40 ? last : null,
      topics: topics,
      strengths: strings(json['strengths']),
      weaknesses: strings(json['weaknesses']),
      enrolled: [
        if (json['enrolled'] case final List ids)
          for (final id in ids.take(maxEnrolled))
            if (id is String && RegExp(r'^[a-z0-9_]{1,60}$').hasMatch(id)) id,
      ],
    );
  }

  static String _clip(String s) =>
      s.length > _maxText ? s.substring(0, _maxText) : s;
}

/// Reports for every learner on this device who is in [group] — what a
/// student device sends its teacher on sync. [deviceKey] makes each
/// learner's key unique across devices.
Future<List<ProgressReport>> buildProgressReports(
  OticDatabase db,
  ClassGroup group, {
  required String deviceKey,
}) async {
  final learners = await (db.select(
    db.students,
  )..where((t) => t.classGroupId.equals(group.id))).get();
  final out = <ProgressReport>[];
  for (final s in learners) {
    final progress =
        await (db.select(db.topicProgress)
              ..where((t) => t.studentId.equals(s.id))
              ..orderBy([(t) => OrderingTerm.desc(t.lastStudiedAt)])
              ..limit(ProgressReport.maxTopics))
            .get();
    out.add(
      ProgressReport(
        memberKey: '$deviceKey/${s.id}',
        name: s.name,
        points: s.totalPoints,
        streakDays: s.streakDays,
        lessonsCompleted: s.totalLessonsCompleted,
        practiceAttempted: s.totalPracticeAttempted,
        practiceCorrect: s.totalPracticeCorrect,
        scenariosCompleted: s.totalScenariosCompleted,
        lastActive: s.lastActiveAt.toUtc().toIso8601String(),
        topics: [for (final p in progress) (topic: p.topic, level: p.level)],
        strengths: _list(s.strengthsJson),
        weaknesses: _list(s.weaknessesJson),
        enrolled: (await db.classSyncDao.enrolledSubjects(
          s.id,
        )).take(ProgressReport.maxEnrolled).toList(),
      ),
    );
  }
  return out;
}

List<String> _list(String json) {
  try {
    final v = jsonDecode(json);
    return [
      if (v is List)
        for (final s in v)
          if (s is String) s,
    ];
  } catch (_) {
    return const [];
  }
}
