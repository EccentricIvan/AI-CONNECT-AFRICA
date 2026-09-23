import 'package:drift/drift.dart';

/// A class, optionally split into a stream — e.g. "S2" / "East".
///
/// A stream is a parallel section of one class, so it is modelled as an
/// optional label on the class row rather than a second table: "S2 East" and
/// "S2 West" are two rows. A learner belongs to at most one row at a time, via
/// `students.class_group_id`.
class ClassGroups extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get className => text()();

  /// Null when the class has no streams.
  TextColumn get streamName => text().nullable()();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
}
