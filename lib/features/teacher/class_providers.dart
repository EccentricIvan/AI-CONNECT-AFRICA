import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../db/daos/class_group_dao.dart';
import '../../db/otic_database.dart';
import '../../db/providers/db_provider.dart';

/// Every class/stream, alphabetical.
final classGroupsProvider = StreamProvider<List<ClassGroup>>((ref) {
  if (kIsWeb) return Stream.value(const []);
  return ref.watch(dbProvider).classGroupDao.watchAllClasses();
});

/// Every learner profile on this device, alphabetical.
final allLearnersProvider = StreamProvider<List<Student>>((ref) {
  if (kIsWeb) return Stream.value(const []);
  return ref.watch(dbProvider).studentDao.watchAllStudents();
});

/// Per-learner progress numbers, keyed by student id.
final learnerStatsProvider = StreamProvider<Map<int, LearnerStats>>((ref) {
  if (kIsWeb) return Stream.value(const {});
  return ref.watch(dbProvider).classGroupDao.watchLearnerStats();
});

/// "S2 East", or just "S2" for a class with no streams.
String classLabel(ClassGroup group) {
  final stream = group.streamName?.trim() ?? '';
  return stream.isEmpty ? group.className : '${group.className} $stream';
}

/// Learners with no recorded study for this long are flagged to the teacher.
const kInactiveAfter = Duration(days: 7);

/// Average mastery (0–100) below which a learner who *has* studied is flagged.
const kLowMastery = 25;

/// Why a learner may need the teacher's attention, or null when they don't.
///
/// Deliberately two plain rules a teacher can check against the numbers on
/// screen — not a score.
String? needsHelpReason(Student learner, LearnerStats stats, DateTime now) {
  if (stats.topics == 0) return 'Not started';
  if (now.difference(learner.lastActiveAt) > kInactiveAfter) {
    return 'Inactive ${now.difference(learner.lastActiveAt).inDays} days';
  }
  if (stats.averageLevel < kLowMastery) return 'Low mastery';
  return null;
}
