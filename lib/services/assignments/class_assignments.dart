import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../collaboration/sync/sync_ids.dart';
import '../../db/otic_database.dart';
import '../../db/providers/db_provider.dart';

/// Topic key of a class assignment's row. Like the PDF marker and quiz
/// rows it is part of a note, so it is signed with the teacher's channel,
/// shared only with the classes the teacher ticks, and never searched.
const kAssignmentTopicKey = '~assignment';

/// The answer a learner may send, at most.
const kMaxAnswerChars = 4000;

/// A teacher's assignment to a class: what learners see and answer.
class ClassAssignment {
  const ClassAssignment({
    required this.id,
    required this.subjectId,
    required this.title,
    required this.instructions,
    required this.maxPoints,
    this.due,
    this.documentTitle = '',
  });

  final String id;
  final String subjectId;
  final String title;
  final String instructions;
  final int maxPoints;

  /// ISO-8601 date, or null.
  final String? due;

  /// The note it travels in.
  final String documentTitle;

  String format() =>
      '[ASSIGNMENT] ${jsonEncode({'id': id, 'title': title, 'instructions': instructions, 'max': maxPoints, 'due': due})}';

  static ClassAssignment? parse(TopicResource row) {
    final text = row.contentChunk.trim();
    if (!text.startsWith('[ASSIGNMENT] ')) return null;
    try {
      final j = jsonDecode(text.substring('[ASSIGNMENT] '.length));
      if (j is! Map) return null;
      final id = j['id'], title = j['title'], max = j['max'];
      if (id is! String || title is! String || max is! int || max <= 0) {
        return null;
      }
      return ClassAssignment(
        id: id,
        subjectId: row.subjectId,
        title: title,
        instructions: j['instructions'] is String
            ? j['instructions'] as String
            : '',
        maxPoints: max,
        due: j['due'] is String ? j['due'] as String : null,
        documentTitle: row.documentTitle ?? row.resourceTitle,
      );
    } catch (_) {
      return null;
    }
  }
}

/// A submission as it travels in a learner's progress report.
class SubmissionPayload {
  const SubmissionPayload({
    required this.uuid,
    required this.assignmentId,
    required this.subjectId,
    required this.answer,
    required this.createdAt,
  });

  final String uuid;
  final String assignmentId;
  final String subjectId;
  final String answer;
  final String createdAt;

  Map<String, Object?> toJson() => {
    'uuid': uuid,
    'assignment': assignmentId,
    'subject': subjectId,
    'answer': answer,
    'created_at': createdAt,
  };

  /// Null when [json] isn't one. Clipped, so a device can't bloat the
  /// teacher's database.
  static SubmissionPayload? fromJson(Object? json) {
    if (json is! Map) return null;
    final uuid = json['uuid'], a = json['assignment'], s = json['subject'];
    final answer = json['answer'], at = json['created_at'];
    if (uuid is! String ||
        uuid.isEmpty ||
        uuid.length > 64 ||
        a is! String ||
        a.length > 64 ||
        s is! String ||
        s.length > 60 ||
        answer is! String ||
        at is! String ||
        at.length > 40) {
      return null;
    }
    return SubmissionPayload(
      uuid: uuid,
      assignmentId: a,
      subjectId: s,
      answer: answer.length > kMaxAnswerChars
          ? answer.substring(0, kMaxAnswerChars)
          : answer,
      createdAt: at,
    );
  }
}

/// A grade as it travels back to the learner's device.
class GradePayload {
  const GradePayload({
    required this.uuid,
    required this.grade,
    required this.version,
    this.feedback,
    this.gradedAt,
  });

  final String uuid;
  final int grade;
  final int version;
  final String? feedback;
  final String? gradedAt;

  Map<String, Object?> toJson() => {
    'uuid': uuid,
    'grade': grade,
    'version': version,
    'feedback': feedback,
    'graded_at': gradedAt,
  };

  static GradePayload? fromJson(Object? json) {
    if (json is! Map) return null;
    final uuid = json['uuid'], grade = json['grade'], v = json['version'];
    if (uuid is! String || grade is! int || v is! int || v <= 0) return null;
    final feedback = json['feedback'];
    return GradePayload(
      uuid: uuid,
      grade: grade,
      version: v,
      feedback: feedback is String
          ? (feedback.length > 1000 ? feedback.substring(0, 1000) : feedback)
          : null,
      gradedAt: json['graded_at'] is String ? json['graded_at'] as String : null,
    );
  }
}

/// Class assignments, submissions and grades.
class ClassAssignments {
  ClassAssignments(this._db);

  final OticDatabase _db;

  // ── Teacher ───────────────────────────────────────────────────────────

  /// Writes a new assignment into this device's notes for [subjectId]; the
  /// teacher shares it with classes like any note. Returns its document
  /// title.
  Future<String?> create({
    required String subjectId,
    required String title,
    required String instructions,
    required int maxPoints,
    String? due,
    int termMarker = 0,
  }) async {
    final t = title.trim();
    if (t.isEmpty || maxPoints <= 0) return null;
    final documentTitle = 'Assignment — $t';
    final a = ClassAssignment(
      id: newSyncId(),
      subjectId: subjectId,
      title: t,
      instructions: instructions.trim(),
      maxPoints: maxPoints,
      due: due,
    );
    final at = DateTime.now().toUtc().toIso8601String();
    await _db
        .into(_db.topicResources)
        .insert(
          TopicResourcesCompanion.insert(
            subjectId: subjectId,
            topicKey: kAssignmentTopicKey,
            termMarker: Value(termMarker),
            resourceTitle: documentTitle,
            contentChunk: a.format(),
            createdAt: at,
            documentTitle: Value(documentTitle),
            updatedAt: Value(at),
          ),
        );
    return documentTitle;
  }

  /// This device's own assignments (the ones it may grade).
  Future<List<ClassAssignment>> own() async => [
    for (final r in await (_db.select(_db.topicResources)
          ..where((t) => t.topicKey.equals(kAssignmentTopicKey))
          ..where((t) => t.classGroupUuid.isNull()))
        .get())
      ?ClassAssignment.parse(r),
  ];

  /// Grades a submission. The version goes up by one, so the learner's
  /// device takes it over any earlier grade.
  Future<void> grade(String submissionUuid, int grade, String? feedback) async {
    final row = await (_db.select(
      _db.assignmentSubmissions,
    )..where((t) => t.uuid.equals(submissionUuid))).getSingleOrNull();
    if (row == null) return;
    await (_db.update(
      _db.assignmentSubmissions,
    )..where((t) => t.id.equals(row.id))).write(
      AssignmentSubmissionsCompanion(
        grade: Value(grade),
        feedback: Value(feedback?.trim().isEmpty ?? true ? null : feedback),
        gradeVersion: Value(row.gradeVersion + 1),
        gradedAt: Value(DateTime.now().toUtc().toIso8601String()),
      ),
    );
  }

  Stream<List<AssignmentSubmission>> watchSubmissions(String assignmentId) =>
      (_db.select(_db.assignmentSubmissions)
            ..where((t) => t.assignmentId.equals(assignmentId))
            ..orderBy([(t) => OrderingTerm.asc(t.learnerName)]))
          .watch();

  // ── Learner ───────────────────────────────────────────────────────────

  /// Assignments a learner in [classUuid] may see: this device's own, and
  /// those received for their class.
  Future<List<ClassAssignment>> visible(String? classUuid) async => [
    for (final r in await (_db.select(_db.topicResources)
          ..where((t) => t.topicKey.equals(kAssignmentTopicKey))
          ..where(
            (t) => classUuid == null
                ? t.classGroupUuid.isNull()
                : t.classGroupUuid.isNull() |
                      t.classGroupUuid.equals(classUuid),
          ))
        .get())
      ?ClassAssignment.parse(r),
  ];

  /// Saves [student]'s answer. A new answer is a new submission; nothing
  /// earlier is overwritten.
  Future<void> submit({
    required Student student,
    required ClassAssignment assignment,
    required String answer,
    required String memberKey,
  }) async {
    final text = answer.trim();
    if (text.isEmpty) return;
    await _db
        .into(_db.assignmentSubmissions)
        .insert(
          AssignmentSubmissionsCompanion.insert(
            uuid: newSyncId(),
            assignmentId: assignment.id,
            subjectId: assignment.subjectId,
            studentId: Value(student.id),
            memberKey: memberKey,
            learnerName: student.name,
            answer: text.length > kMaxAnswerChars
                ? text.substring(0, kMaxAnswerChars)
                : text,
            createdAt: DateTime.now().toUtc().toIso8601String(),
          ),
        );
  }

  Stream<List<AssignmentSubmission>> watchMine(int studentId) =>
      (_db.select(_db.assignmentSubmissions)
            ..where((t) => t.studentId.equals(studentId))
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
          .watch();

  // ── Sync ──────────────────────────────────────────────────────────────

  /// [studentId]'s submissions to assignments received for [classUuid] —
  /// what their progress report carries to the teacher.
  Future<List<SubmissionPayload>> outgoing(
    int studentId,
    String classUuid,
  ) async {
    final ids = {
      for (final a in await _received(classUuid)) a.id,
    };
    if (ids.isEmpty) return const [];
    final rows =
        await (_db.select(_db.assignmentSubmissions)
              ..where((t) => t.studentId.equals(studentId))
              ..where((t) => t.assignmentId.isIn(ids))
              ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
              ..limit(20))
            .get();
    return [
      for (final r in rows)
        SubmissionPayload(
          uuid: r.uuid,
          assignmentId: r.assignmentId,
          subjectId: r.subjectId,
          answer: r.answer,
          createdAt: r.createdAt,
        ),
    ];
  }

  Future<List<ClassAssignment>> _received(String classUuid) async => [
    for (final r in await (_db.select(_db.topicResources)
          ..where((t) => t.topicKey.equals(kAssignmentTopicKey))
          ..where((t) => t.classGroupUuid.equals(classUuid)))
        .get())
      ?ClassAssignment.parse(r),
  ];

  /// On the teacher's device: stores what [memberKey] submitted, only for
  /// this device's own assignments shared with [classUuid] — a learner
  /// can't answer anything else, or edit an answer already received.
  /// Returns the grades of those submissions to send back.
  Future<List<GradePayload>> receive({
    required String classUuid,
    required String memberKey,
    required String learnerName,
    required List<SubmissionPayload> submissions,
  }) async {
    if (submissions.isEmpty) return const [];
    final shared = {
      for (final s in await (_db.select(
        _db.resourceShares,
      )..where((t) => t.classGroupUuid.equals(classUuid))).get())
        (s.subjectId, s.documentTitle),
    };
    final allowed = {
      for (final a in await own())
        if (shared.contains((a.subjectId, a.documentTitle))) a.id,
    };
    final out = <GradePayload>[];
    for (final s in submissions) {
      if (!allowed.contains(s.assignmentId)) continue;
      final existing = await (_db.select(
        _db.assignmentSubmissions,
      )..where((t) => t.uuid.equals(s.uuid))).getSingleOrNull();
      if (existing == null) {
        await _db
            .into(_db.assignmentSubmissions)
            .insert(
              AssignmentSubmissionsCompanion.insert(
                uuid: s.uuid,
                assignmentId: s.assignmentId,
                subjectId: s.subjectId,
                memberKey: memberKey,
                learnerName: learnerName,
                answer: s.answer,
                createdAt: s.createdAt,
                receivedAt: Value(DateTime.now().toUtc().toIso8601String()),
              ),
            );
        continue;
      }
      // Never another learner's row, and never a new answer in an old one.
      if (existing.memberKey != memberKey) continue;
      if (existing.grade != null && existing.gradeVersion > 0) {
        out.add(
          GradePayload(
            uuid: existing.uuid,
            grade: existing.grade!,
            version: existing.gradeVersion,
            feedback: existing.feedback,
            gradedAt: existing.gradedAt,
          ),
        );
      }
    }
    return out;
  }

  /// On the teacher's device: which of [uuids] it holds as [memberKey]'s
  /// answers — what the reply tells the learner's device arrived.
  Future<List<String>> heldFrom(String memberKey, Iterable<String> uuids) async {
    final wanted = uuids.toSet();
    if (wanted.isEmpty) return const [];
    return [
      for (final r in await (_db.select(_db.assignmentSubmissions)
            ..where((t) => t.uuid.isIn(wanted))
            ..where((t) => t.memberKey.equals(memberKey)))
          .get())
        r.uuid,
    ];
  }

  /// On the learner's device: its answers the teacher's device confirmed it
  /// holds. Returns how many were newly marked.
  Future<int> markReceived(Iterable<String> uuids) async {
    final wanted = uuids.toSet();
    if (wanted.isEmpty) return 0;
    return (_db.update(_db.assignmentSubmissions)
          ..where((t) => t.uuid.isIn(wanted))
          ..where((t) => t.studentId.isNotNull())
          ..where((t) => t.receivedAt.isNull()))
        .write(
          AssignmentSubmissionsCompanion(
            receivedAt: Value(DateTime.now().toUtc().toIso8601String()),
          ),
        );
  }

  /// On the learner's device: takes grades newer than the ones it holds,
  /// for its own submissions only. Returns how many changed.
  Future<int> applyGrades(List<GradePayload> grades) async {
    var changed = 0;
    for (final g in grades) {
      final row = await (_db.select(
        _db.assignmentSubmissions,
      )..where((t) => t.uuid.equals(g.uuid))).getSingleOrNull();
      if (row == null || row.studentId == null) continue;
      if (g.version <= row.gradeVersion) continue;
      await (_db.update(
        _db.assignmentSubmissions,
      )..where((t) => t.id.equals(row.id))).write(
        AssignmentSubmissionsCompanion(
          grade: Value(g.grade),
          feedback: Value(g.feedback),
          gradeVersion: Value(g.version),
          gradedAt: Value(g.gradedAt),
          receivedAt: Value(
            row.receivedAt ?? DateTime.now().toUtc().toIso8601String(),
          ),
        ),
      );
      changed++;
    }
    return changed;
  }
}

final classAssignmentsProvider = Provider<ClassAssignments>(
  (ref) => ClassAssignments(ref.watch(dbProvider)),
);
