import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../otic_database.dart';

// ── Database singleton ────────────────────────────────────────────────────────

final dbProvider = Provider<OticDatabase>((ref) {
  final db = OticDatabase();
  ref.onDispose(db.close);
  return db;
});

// ── Student ───────────────────────────────────────────────────────────────────

/// The active student profile, or null if no profile created yet.
final activeStudentProvider = FutureProvider<Student?>((ref) {
  if (kIsWeb) return Future.value(null);
  final db = ref.watch(dbProvider);
  return db.studentDao.getActiveStudent();
});

/// True if the device has an existing student profile.
final hasProfileProvider = FutureProvider<bool>((ref) async {
  if (kIsWeb) return false;
  final student = await ref.watch(activeStudentProvider.future);
  return student != null;
});

// ── Session history ───────────────────────────────────────────────────────────

final recentSessionsProvider =
    FutureProvider.family((ref, int studentId) {
  final db = ref.watch(dbProvider);
  return db.sessionDao.getRecentSessions(studentId, limit: 20);
});

final topicProgressProvider =
    FutureProvider.family((ref, int studentId) {
  final db = ref.watch(dbProvider);
  return db.sessionDao.getTopicProgress(studentId);
});

// ── Student notifier (create / update) ───────────────────────────────────────

class StudentNotifier extends AsyncNotifier<Student?> {
  @override
  Future<Student?> build() async {
    final db = ref.watch(dbProvider);
    return db.studentDao.getActiveStudent();
  }

  Future<void> createProfile({
    required String name,
    int? age,
    String? grade,
    String language = 'en',
    List<String> interests = const [],
    String learningStyle = 'unknown',
  }) async {
    final db = ref.read(dbProvider);
    final id = await db.studentDao.createStudent(
      StudentsCompanion.insert(
        name: name,
        age: Value(age),
        grade: Value(grade),
        language: Value(language),
        interestsJson: Value(_toJson(interests)),
        learningStyle: Value(learningStyle),
        createdAt: Value(DateTime.now()),
        lastActiveAt: Value(DateTime.now()),
      ),
    );
    state = AsyncData(await db.studentDao.getStudentById(id));
    ref.invalidate(activeStudentProvider);
    ref.invalidate(hasProfileProvider);
  }

  Future<void> touch(int id) async {
    final db = ref.read(dbProvider);
    await db.studentDao.touchStudent(id);
  }

  /// Updates the existing profile in place — unlike [createProfile], this
  /// never inserts a second row (which would leave two students competing
  /// for "active" and break [getActiveStudent]'s single-row assumption).
  /// Fields left null are left untouched in the DB (except [name], which is
  /// always required and always overwrites) — a caller updating just one
  /// field, e.g. only `language`, must not silently wipe the others.
  Future<void> updateProfile({
    required int id,
    required String name,
    int? age,
    String? grade,
    String? language,
    List<String>? interests,
    String? learningStyle,
  }) async {
    final db = ref.read(dbProvider);
    await db.studentDao.updateStudent(
      StudentsCompanion(
        id: Value(id),
        name: Value(name),
        age: age != null ? Value(age) : const Value.absent(),
        grade: grade != null ? Value(grade) : const Value.absent(),
        language: language != null ? Value(language) : const Value.absent(),
        interestsJson: interests != null ? Value(_toJson(interests)) : const Value.absent(),
        learningStyle: learningStyle != null ? Value(learningStyle) : const Value.absent(),
        lastActiveAt: Value(DateTime.now()),
      ),
    );
    state = AsyncData(await db.studentDao.getStudentById(id));
    ref.invalidate(activeStudentProvider);
  }

  String _toJson(List<String> list) =>
      '[${list.map((s) => '"$s"').join(',')}]';
}

final studentNotifierProvider =
    AsyncNotifierProvider<StudentNotifier, Student?>(StudentNotifier.new);

// ── Badges ────────────────────────────────────────────────────────────────────

final earnedBadgesProvider = FutureProvider.family((ref, int studentId) {
  final db = ref.watch(dbProvider);
  return db.badgeDao.getBadgesForStudent(studentId);
});

// ── Projects ──────────────────────────────────────────────────────────────────

final studentProjectsProvider = FutureProvider.family((ref, int studentId) {
  final db = ref.watch(dbProvider);
  return db.projectDao.getProjectsForStudent(studentId);
});

// ── Websites ──────────────────────────────────────────────────────────────────

final studentWebsitesProvider = FutureProvider.family((ref, int studentId) {
  final db = ref.watch(dbProvider);
  return db.websiteDao.getWebsitesForStudent(studentId);
});
