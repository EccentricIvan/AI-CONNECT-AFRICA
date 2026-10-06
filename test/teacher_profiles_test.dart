import 'package:ai_connect_africa/db/otic_database.dart';
import 'package:ai_connect_africa/features/teacher/teacher_profiles.dart';
import 'package:ai_connect_africa/services/custom_subject_service.dart';
import 'package:ai_connect_africa/services/offline_storage_service.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late OticDatabase db;
  late TeacherProfileService teachers;
  late CustomSubjectService subjects;

  setUp(() {
    db = OticDatabase.forTesting(DatabaseConnection(NativeDatabase.memory()));
    teachers = TeacherProfileService(db);
    subjects = CustomSubjectService(db, OfflineStorageService(db));
  });
  tearDown(() => db.close());

  Future<int> addTeacher(String name, String pin) async =>
      (await teachers.create(name: name, pin: pin)).profile!.id;

  group('profiles', () {
    test('sign in only with that teacher’s own PIN', () async {
      final amina = await addTeacher('Amina', '1234');
      final okello = await addTeacher('Okello', '9876');
      expect((await teachers.signIn(amina, '1234'))?.name, 'Amina');
      expect(await teachers.signIn(amina, '9876'), isNull);
      expect((await teachers.signIn(okello, '9876'))?.name, 'Okello');
    });

    test('a name is taken once; a PIN is 4 to 8 digits', () async {
      await addTeacher('Amina', '1234');
      expect((await teachers.create(name: 'amina', pin: '5555')).error,
          isNotNull);
      expect((await teachers.create(name: 'Okello', pin: '12')).error,
          isNotNull);
      expect((await teachers.create(name: '  ', pin: '1234')).error,
          isNotNull);
    });

    test('a PIN changes only with the current one', () async {
      final amina = await addTeacher('Amina', '1234');
      expect(await teachers.changePin(amina, '0000', '4321'), isFalse);
      expect(await teachers.changePin(amina, '1234', '4321'), isTrue);
      expect(await teachers.signIn(amina, '1234'), isNull);
      expect(await teachers.signIn(amina, '4321'), isNotNull);
    });

    test('the first teacher takes over what was made before profiles',
        () async {
      final oldClass = await db.classGroupDao.createClass(className: 'S1');
      final bio = (await subjects.create(name: 'Biology 9')).subjectId!;
      final amina = await addTeacher('Amina', '1234');
      await addTeacher('Okello', '9876');

      final c = await (db.select(db.classGroups)
            ..where((t) => t.id.equals(oldClass)))
          .getSingle();
      expect(c.ownerTeacherId, amina);
      expect((await subjects.find(bio))!.ownerTeacherId, amina);
    });
  });

  group('only the creator changes a class or stream', () {
    test('the owner renames and deletes; another teacher cannot', () async {
      final amina = await addTeacher('Amina', '1234');
      final okello = await addTeacher('Okello', '9876');
      final id = await db.classGroupDao.createClass(
        className: 'S2',
        streamName: 'East',
        ownerTeacherId: amina,
      );

      expect(
        await db.classGroupDao.renameClass(
          id,
          className: 'S3',
          byTeacherId: okello,
        ),
        isFalse,
      );
      expect(await db.classGroupDao.deleteClass(id, byTeacherId: okello),
          isFalse);
      final row = await (db.select(db.classGroups)
            ..where((t) => t.id.equals(id)))
          .getSingle();
      expect(row.className, 'S2');

      expect(
        await db.classGroupDao.renameClass(
          id,
          className: 'S3',
          byTeacherId: amina,
        ),
        isTrue,
      );
      expect(await db.classGroupDao.deleteClass(id, byTeacherId: amina),
          isTrue);
    });
  });

  group('only the creator changes a subject and its materials', () {
    test('another teacher cannot rename or delete it, or its notes',
        () async {
      final amina = await addTeacher('Amina', '1234');
      final okello = await addTeacher('Okello', '9876');
      final id = (await subjects.create(
        name: 'Chemistry 2',
        ownerTeacherId: amina,
      )).subjectId!;
      await OfflineStorageService(db).insertTopicResource(
        subjectId: id,
        topicKey: 'Acids',
        resourceTitle: 'Acids',
        content: 'An acid turns blue litmus paper red.',
      );

      expect(await subjects.mayChange(id, okello), isFalse);
      expect(await subjects.rename(id, 'Chem', byTeacherId: okello),
          isFalse);
      expect(await subjects.delete(id, byTeacherId: okello),
          isFalse);
      expect(await subjects.find(id), isNotNull);
      expect(
        await (db.select(db.topicResources)
              ..where((t) => t.subjectId.equals(id)))
            .get(),
        isNotEmpty,
        reason: 'the notes stay',
      );

      expect(await subjects.mayChange(id, amina), isTrue);
      expect(await subjects.delete(id, byTeacherId: amina),
          isTrue);
      expect(await subjects.find(id), isNull);
    });

    test('a subject received from a class is nobody’s to change', () async {
      final amina = await addTeacher('Amina', '1234');
      await db.into(db.customSubjects).insert(
            CustomSubjectsCompanion.insert(
              subjectId: 'physics-x',
              name: 'Physics X',
              createdAt: DateTime.now().toUtc().toIso8601String(),
              classGroupUuid: const Value('class-uuid'),
              ownerTeacherId: Value(amina),
            ),
          );
      expect(await subjects.mayChange('physics-x', amina), isFalse);
    });
  });
}
