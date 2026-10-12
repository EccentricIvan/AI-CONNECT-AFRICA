import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../db/otic_database.dart';
import '../../db/providers/db_provider.dart';
import '../../services/assignments/class_assignments.dart';
import '../sync/progress_report.dart' show reportDeviceKey;

/// The school cloud plug-in point.
///
/// The app is offline-first and never needs a server: every feature works
/// over the local network alone. A school that also runs a cloud server
/// (e.g. a hosted backend) plugs it in here by overriding
/// [cloudSyncAdapterProvider]. Until then [DisabledCloudSync] is used and
/// nothing leaves the device.
///
/// Records are queued in `cloud_outbox` as they are made, whatever the
/// adapter, so work done before the plug-in is turned on, or while offline,
/// is sent later. Each record has a stable [CloudRecord.id]; the server
/// must treat a repeat as a no-op, so a retry never doubles anything.
class CloudRecord {
  const CloudRecord({
    required this.id,
    required this.kind,
    required this.payload,
  });

  /// Stable, e.g. `submission:<uuid>`.
  final String id;

  /// [CloudKind] name.
  final String kind;
  final Map<String, Object?> payload;
}

/// What the outbox carries.
abstract final class CloudKind {
  /// A teacher's assignment, homework or holiday assessment.
  static const assignment = 'assignment';

  /// A learner's answer.
  static const submission = 'submission';

  /// A teacher's grade (one record per grade version).
  static const grade = 'grade';
}

abstract class CloudSyncAdapter {
  const CloudSyncAdapter();

  /// False: records stay queued and nothing is sent.
  bool get enabled;

  /// Sends [records]; returns the ids the server now holds (including ones
  /// it already had). Throwing leaves them all queued.
  Future<Set<String>> push(List<CloudRecord> records);
}

/// The default: no cloud.
class DisabledCloudSync extends CloudSyncAdapter {
  const DisabledCloudSync();

  @override
  bool get enabled => false;

  @override
  Future<Set<String>> push(List<CloudRecord> records) async => const {};
}

/// Override to plug a school cloud in.
final cloudSyncAdapterProvider = Provider<CloudSyncAdapter>(
  (ref) => const DisabledCloudSync(),
);

/// Queues records and sends them through the adapter.
class CloudOutboxService {
  CloudOutboxService(this._db, this._adapter);

  final OticDatabase _db;
  final CloudSyncAdapter _adapter;

  static const batchSize = 50;

  /// Queues one record. Queuing the same [recordId] twice changes nothing.
  Future<void> enqueue(String kind, String refUuid, {String? recordId}) => _db
      .into(_db.cloudOutbox)
      .insert(
        CloudOutboxCompanion.insert(
          recordId: recordId ?? '$kind:$refUuid',
          kind: kind,
          refUuid: refUuid,
          createdAt: DateTime.now().toUtc().toIso8601String(),
        ),
        mode: InsertMode.insertOrIgnore,
      );

  /// Records not yet accepted by the cloud.
  Future<int> pending() async => (await (_db.select(
    _db.cloudOutbox,
  )..where((t) => t.sentAt.isNull())).get()).length;

  /// Sends what is queued, oldest first. Returns how many the cloud
  /// accepted; 0 when the plug-in is off or unreachable.
  Future<int> flush() async {
    if (!_adapter.enabled) return 0;
    var accepted = 0;
    while (true) {
      final rows =
          await (_db.select(_db.cloudOutbox)
                ..where((t) => t.sentAt.isNull())
                ..orderBy([(t) => OrderingTerm.asc(t.id)])
                ..limit(batchSize))
              .get();
      if (rows.isEmpty) return accepted;
      final records = <CloudRecord>[];
      final gone = <int>[];
      for (final r in rows) {
        final payload = await _payload(r);
        if (payload == null) {
          gone.add(r.id);
        } else {
          records.add(
            CloudRecord(id: r.recordId, kind: r.kind, payload: payload),
          );
        }
      }
      // Deleted meanwhile (a wiped learner, a deleted note): never sent.
      if (gone.isNotEmpty) {
        await (_db.delete(_db.cloudOutbox)..where((t) => t.id.isIn(gone))).go();
      }
      if (records.isEmpty) continue;
      final Set<String> ok;
      try {
        ok = await _adapter.push(records);
      } catch (e) {
        debugPrint('Cloud sync: kept queued ($e)');
        return accepted;
      }
      final now = DateTime.now().toUtc().toIso8601String();
      await (_db.update(_db.cloudOutbox)
            ..where((t) => t.recordId.isIn(ok) & t.sentAt.isNull()))
          .write(CloudOutboxCompanion(sentAt: Value(now)));
      accepted += ok.length;
      // The server took none of a full batch: stop rather than loop.
      if (ok.isEmpty) return accepted;
    }
  }

  /// The record's content as it is now, or null when it no longer exists.
  Future<Map<String, Object?>?> _payload(CloudOutboxEntry e) async {
    switch (e.kind) {
      case CloudKind.assignment:
        final rows =
            await (_db.select(_db.topicResources)
                  ..where((t) => t.topicKey.equals(kAssignmentTopicKey))
                  ..where((t) => t.classGroupUuid.isNull()))
                .get();
        for (final r in rows) {
          final a = ClassAssignment.parse(r);
          if (a != null && a.id == e.refUuid) {
            return {
              ...a.toJson(),
              'subject': a.subjectId,
              'document': a.documentTitle,
            };
          }
        }
        return null;
      case CloudKind.submission:
      case CloudKind.grade:
        final s = await (_db.select(
          _db.assignmentSubmissions,
        )..where((t) => t.uuid.equals(e.refUuid))).getSingleOrNull();
        if (s == null) return null;
        final who = await _learner(s);
        if (e.kind == CloudKind.grade) {
          if (s.grade == null) return null;
          return {
            'uuid': s.uuid,
            'assignment': s.assignmentId,
            ...who,
            'grade': s.grade,
            'feedback': s.feedback,
            'version': s.gradeVersion,
            'graded_at': s.gradedAt,
          };
        }
        return {
          ...SubmissionPayload(
            uuid: s.uuid,
            assignmentId: s.assignmentId,
            subjectId: s.subjectId,
            answer: s.answer,
            createdAt: s.createdAt,
            startedAt: s.startedAt,
          ).toJson(),
          ...who,
          'name': s.learnerName,
        };
    }
    return null;
  }

  /// The learner as every device names them: the member key their
  /// progress reports use (`deviceKey/studentId`, the same on the learner's
  /// and the teacher's device) and, on the learner's own device, their
  /// portable uuid. The school is the adapter's to add.
  Future<Map<String, Object?>> _learner(AssignmentSubmission s) async {
    final id = s.studentId;
    if (id == null) return {'member': s.memberKey};
    final student = await (_db.select(
      _db.students,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return {
      'member': '${await reportDeviceKey(_db)}/$id',
      'learner_uuid': student?.uuid,
    };
  }
}

final cloudOutboxProvider = Provider<CloudOutboxService>(
  (ref) => CloudOutboxService(
    ref.watch(dbProvider),
    ref.watch(cloudSyncAdapterProvider),
  ),
);
