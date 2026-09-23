import 'package:drift/drift.dart';
import 'students_table.dart';

/// One saved App Builder generation (App Dev Lab → App Builder chat flow).
///
/// Mirrors [WebsiteProjects]: the coder's output is a single self-contained
/// HTML5 document (same offline, no-CDN contract as the website builder), so
/// there is nothing else to reconstruct a save from besides that document
/// and the answers that produced it.
class AppBuilderProjects extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get studentId =>
      integer().references(Students, #id, onDelete: KeyAction.cascade)();
  TextColumn get title => text()();
  TextColumn get appTypeId => text()();
  TextColumn get appTypeName => text()();
  TextColumn get themeColor => text().withDefault(const Constant('#2563EB'))();
  // The generated (and possibly student-edited) HTML document.
  TextColumn get htmlContent => text()();
  // Optional downloadable FastAPI backend scaffold — export-only, never run
  // on-device. Null until the student asks for one.
  TextColumn get backendContent => text().nullable()();
  // JSON map of the answers recorded in the chat flow (name, purpose, …).
  TextColumn get answersJson => text().withDefault(const Constant('{}'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
