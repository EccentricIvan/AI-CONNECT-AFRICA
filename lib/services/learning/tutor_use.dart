import 'package:flutter_riverpod/flutter_riverpod.dart';

/// When the tutor last replied to the active learner, in memory only: set
/// while a chat reply streams and when it lands, and when Practice gives
/// feedback on a scenario.
///
/// A quiz answer given after the tutor replied (and after the question
/// appeared) is marked "Tutor used". That records that the two happened
/// together on this device, not that the tutor gave the answer, and it says
/// nothing about help from outside the app. Cleared on every learner switch,
/// so one learner's chat never marks the next learner's answers.
final tutorLastReplyProvider = StateProvider<DateTime?>((ref) => null);

/// Whether the tutor replied after [since].
bool tutorUsedSince(DateTime? lastReply, DateTime since) =>
    lastReply != null && lastReply.isAfter(since);
