import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:http/http.dart' as http;

import '../../db/otic_database.dart';
import '../../db/tables/sync_identity_table.dart' show kRoleTeacher;
import 'class_crypto.dart';
import 'class_share_server.dart'
    show
        kJoinApprovalTimeout,
        kMacHeader,
        kNonceHeader,
        kStandbyHeader,
        kStandbyLedgerPath,
        kStandbyPairPath;
import 'failover_crypto.dart';
import 'routing_envelope.dart';
import 'selective_sync_manager.dart' show SelectiveSyncManager, TeacherEndpoint;

/// Outcome of a failover step that can fail with a message for the screen.
class FailoverResult {
  const FailoverResult.ok() : error = null;
  const FailoverResult.failed(String this.error);
  final String? error;
  bool get ok => error == null;
}

/// What a promotion restored.
class PromotionResult {
  const PromotionResult.promoted({
    required int this.generation,
    required this.classes,
    required this.notes,
  }) : error = null;
  const PromotionResult.failed(String this.error)
    : generation = null,
      classes = 0,
      notes = 0;

  final String? error;
  final int? generation;
  final int classes;

  /// Note chunks written to this device (ones it already had are skipped).
  final int notes;
  bool get ok => error == null;
}

/// Host failover: a standby device that can take over as a school's root
/// teacher device if that device dies, breaks or is lost.
///
/// Students trust the root teacher's **Ed25519 key** and the class's id,
/// not a particular device or address (`SelectiveSyncManager.syncClass`
/// accepts whichever endpoint answers with that key's signature). So the
/// takeover moves the key, not the students:
///
/// 1. **Backup.** The host sets a failover passphrase ([enableFailover]).
///    It pairs a standby (`ClassShareServer.openStandbyCode`, typed code +
///    the teacher's Accept, see [pairAsStandby]). The standby then pulls the
///    host ledger ([pullLedger], [startMirroring]): the signing key, school,
///    classes and their keys, served channel versions, co-teacher roster,
///    shares, the shared notes themselves and the teacher's subjects, all
///    sealed under the passphrase. Hashes alone wouldn't do: a promoted host
///    that can't serve a subject makes every student drop it.
/// 2. **Promotion** ([promoteToHostNode]). The passphrase opens the ledger
///    offline. The device becomes the root teacher device under the same key
///    at **host generation + 1**. Every version it signs then outranks the
///    old device's (see [generationFloor]).
/// 3. **Reconnect.** Students keep their joined class, class key and
///    enrollment unchanged. They find the new device by the usual discovery,
///    or its typed address. Its handshake carries the new `host_epoch`, and
///    from then on they refuse the old device if it comes back, so it can't
///    drop or overwrite notes.
///
/// Known limits: progress reports (`member_reports`) and the standby list
/// are not carried over. Reports re-arrive on each student's next sync, and
/// the new host pairs its own standby. A student that hasn't synced with the
/// new host yet still accepts the old one, as nothing has told it otherwise.
class P2PFailoverService {
  P2PFailoverService(
    this._db, {
    http.Client? client,
    this.kdfRounds = kLedgerKdfRounds,
    this.joinRounds = kJoinKdfRounds,
    this.approvalTimeout = kJoinApprovalTimeout,
  }) : _client = client ?? http.Client();

  final OticDatabase _db;
  final http.Client _client;

  /// PBKDF2 rounds for a newly set passphrase — lowered only in tests. A
  /// ledger records its own rounds, so promotion always uses those.
  final int kdfRounds;

  /// PBKDF2 rounds for the pairing code — lowered only in tests.
  final int joinRounds;
  final Duration approvalTimeout;

  static const _timeout = Duration(seconds: 30);
  Timer? _mirror;

  // ── Host side ───────────────────────────────────────────────────────────

  /// Sets (or changes) the failover passphrase on the root teacher device.
  /// A standby's earlier ledgers stay sealed under the old passphrase until
  /// its next pull.
  Future<FailoverResult> enableFailover(String passphrase) async {
    if (passphrase.trim().length < kMinPassphraseLength) {
      return const FailoverResult.failed(
        'Passphrase must be at least $kMinPassphraseLength characters',
      );
    }
    final me = await _db.classSyncDao.identity();
    if (me.schoolId == null) {
      return const FailoverResult.failed('Set the school first');
    }
    final salt = newNonce();
    final key = await deriveLedgerKey(passphrase, salt, rounds: kdfRounds);
    await (_db.update(_db.syncIdentity)..where((t) => t.id.equals(1))).write(
      SyncIdentityCompanion(
        failoverSealKey: Value(key),
        failoverKdfSalt: Value(salt),
        failoverKdfRounds: Value(kdfRounds),
      ),
    );
    return const FailoverResult.ok();
  }

  /// This device's current host ledger, sealed — the same thing a standby
  /// pulls, for carrying on a USB stick instead. Null when no failover
  /// passphrase is set.
  Future<Map<String, dynamic>?> exportLedger() => buildSealedLedger(_db);

  Stream<List<FailoverStandby>> watchStandbys() =>
      _db.select(_db.failoverStandbys).watch();

  /// Unpairs a standby: it can't pull again. A ledger it already holds stays
  /// sealed under the passphrase — change the passphrase too if the device
  /// was lost.
  Future<void> removeStandby(String publicKey) =>
      (_db.delete(_db.failoverStandbys)
            ..where((t) => t.publicKey.equals(publicKey)))
          .go();

  // ── Standby side ────────────────────────────────────────────────────────

  /// Pairs this device as [hosts]' standby with the code shown on the
  /// teacher device, then pulls a first ledger. Waits for the teacher's
  /// Accept.
  Future<FailoverResult> pairAsStandby({
    required List<TeacherEndpoint> hosts,
    required String typedCode,
    String name = '',
  }) async {
    final code = normalizeJoinCode(typedCode);
    if (code == null) {
      return const FailoverResult.failed(
        'Invalid pairing code',
      );
    }
    final me = await _db.classSyncDao.identity();
    final myKey = await signingPublicKey(me.signingSeed);
    final salt = newNonce();
    final secret = await joinSecret(code, salt, rounds: joinRounds);
    final proof = await standbyPairProof(secret, salt, myKey);
    for (final h in await SelectiveSyncManager.reachable(hosts)) {
      final Map<String, Object?> b;
      try {
        final response = await _client
            .post(
              Uri.parse('http://${h.address}:${h.port}/$kStandbyPairPath'),
              headers: const {'content-type': 'application/json'},
              body: jsonEncode({
                'nonce': salt,
                'proof': proof,
                'name': name,
                'device_public_key': myKey,
              }),
            )
            .timeout(approvalTimeout + _timeout);
        if (response.statusCode != 200) continue;
        final opened = await openJoinBundle(
          secret,
          salt,
          (jsonDecode(response.body) as Map)['bundle'],
        );
        if (opened is! Map) continue;
        b = Map<String, Object?>.from(opened);
      } catch (_) {
        continue;
      }
      final schoolId = b['school_id'], rootKey = b['root_public_key'];
      final schoolName = b['school_name'];
      if (schoolId is! String || rootKey is! String) {
        return const FailoverResult.failed(
          'Pairing failed',
        );
      }
      if (me.schoolId != null && me.schoolId != schoolId) {
        return FailoverResult.failed(
          'This device belongs to ${me.schoolName ?? 'another school'}',
        );
      }
      await _db
          .into(_db.hostLedgers)
          .insert(
            HostLedgersCompanion.insert(
              id: const Value(1),
              rootPublicKey: rootKey,
              schoolId: schoolId,
              schoolName: schoolName is String ? schoolName : '',
            ),
            mode: InsertMode.insertOrReplace,
          );
      return pullLedger(hosts);
    }
    return const FailoverResult.failed(
      'Pairing failed. Check the code and try again.',
    );
  }

  /// Pulls the newest ledger from whichever of [hosts] is this device's
  /// paired host, and keeps it if the root key signed it and it is no older
  /// than the one held.
  Future<FailoverResult> pullLedger(List<TeacherEndpoint> hosts) async {
    final held = await storedLedgerRow();
    if (held == null) {
      return const FailoverResult.failed('This device isn’t a standby yet.');
    }
    final me = await _db.classSyncDao.identity();
    final myKey = await signingPublicKey(me.signingSeed);
    for (final h in await SelectiveSyncManager.reachable(hosts)) {
      try {
        final nonce = newNonce();
        const raw = '{}';
        final response = await _client
            .post(
              Uri.parse('http://${h.address}:${h.port}/$kStandbyLedgerPath'),
              headers: {
                'content-type': 'application/json',
                kStandbyHeader: myKey,
                kNonceHeader: nonce,
                kMacHeader: await signStandbyRequest(
                  standbySeed: me.signingSeed,
                  path: kStandbyLedgerPath,
                  nonce: nonce,
                  body: raw,
                ),
              },
              body: raw,
            )
            .timeout(_timeout);
        if (response.statusCode != 200) continue;
        final reply = jsonDecode(response.body);
        if (reply is! Map) continue;
        final ledgerJson = reply['ledger_json'], sig = reply['sig'];
        if (ledgerJson is! String || sig is! String) continue;
        if (!await verifyLedgerReply(
          rootPublicKey: held.rootPublicKey,
          nonce: nonce,
          ledgerJson: ledgerJson,
          signature: sig,
        )) {
          continue;
        }
        final ledger = jsonDecode(ledgerJson);
        if (ledger is! Map) continue;
        final header = ledgerHeader(Map<String, Object?>.from(ledger));
        if (header == null ||
            header.rootPublicKey != held.rootPublicKey ||
            header.schoolId != held.schoolId ||
            header.generation < held.generation) {
          continue;
        }
        await (_db.update(_db.hostLedgers)..where((t) => t.id.equals(1)))
            .write(
              HostLedgersCompanion(
                sealedJson: Value(ledgerJson),
                generation: Value(header.generation),
                receivedAt: Value(DateTime.now()),
              ),
            );
        return const FailoverResult.ok();
      } catch (_) {
        continue;
      }
    }
    return const FailoverResult.failed(
      'Teacher device not reachable',
    );
  }

  /// Keeps this standby's ledger current: pulls every [every] while the
  /// host is reachable. A failed pull keeps the last good ledger.
  /// [hosts] is asked each time, so it can follow discovery.
  void startMirroring(
    FutureOr<List<TeacherEndpoint>> Function() hosts, {
    Duration every = const Duration(minutes: 2),
  }) {
    stopMirroring();
    var busy = false;
    Future<void> tick() async {
      if (busy) return;
      busy = true;
      try {
        await pullLedger(await hosts());
      } finally {
        busy = false;
      }
    }

    _mirror = Timer.periodic(every, (_) => unawaited(tick()));
    unawaited(tick());
  }

  void stopMirroring() {
    _mirror?.cancel();
    _mirror = null;
  }

  Future<HostLedger?> storedLedgerRow() => (_db.select(
    _db.hostLedgers,
  )..where((t) => t.id.equals(1))).getSingleOrNull();

  /// The ledger this standby holds, ready for [promoteToHostNode]. Null
  /// before the first successful pull.
  Future<Map<String, dynamic>?> storedLedger() async {
    final json = (await storedLedgerRow())?.sealedJson;
    if (json == null) return null;
    return Map<String, dynamic>.from(jsonDecode(json) as Map);
  }

  // ── Promotion ───────────────────────────────────────────────────────────

  /// Makes this device the school's root teacher device from [backupLedger]
  /// (pulled by a standby, or carried on USB from [exportLedger]), if
  /// [teacherPassphrase] opens it. Works fully offline.
  ///
  /// Refused on a student device, and on a device that already serves
  /// classes of its own (or co-teaches classes not in this ledger) with a
  /// different key, since taking the root key would cut its own students
  /// off. A co-teacher of these same classes may be promoted: its subjects
  /// fold back into the root's, and the re-signed roster drops its old key.
  /// Running it again with the same ledger is harmless.
  /// The classes and subjects taken over become [ownerTeacherId]'s (the
  /// teacher signed in here).
  Future<PromotionResult> promoteToHostNode(
    String teacherPassphrase,
    Map<String, dynamic> backupLedger, {
    int? ownerTeacherId,
  }) async {
    final ledger = Map<String, Object?>.from(backupLedger);
    final header = ledgerHeader(ledger);
    if (header == null) {
      return const PromotionResult.failed('Not a valid backup');
    }

    // Credentials first: nothing about this device is touched, or even
    // checked, before the passphrase opens the ledger.
    final Map<String, Object?> inner;
    final String ledgerKey;
    try {
      ledgerKey = await deriveLedgerKey(
        teacherPassphrase,
        header.salt,
        rounds: header.rounds,
      );
      inner = await openLedger(ledger, ledgerKey);
    } on SyncTrustError {
      return const PromotionResult.failed(
        'Incorrect passphrase',
      );
    }
    final seed = inner['signing_seed'];
    if (seed is! String ||
        inner['school_id'] != header.schoolId ||
        inner['generation'] != header.generation ||
        await signingPublicKey(seed) != header.rootPublicKey) {
      return const PromotionResult.failed(
        'Backup is damaged',
      );
    }
    final classes = _maps(inner['classes']);
    final classUuids = {
      for (final c in classes)
        if (c['uuid'] case final String u) u,
    };

    final me = await _db.classSyncDao.identity();
    if (me.schoolId != null && me.schoolId != header.schoolId) {
      return PromotionResult.failed(
        'This device belongs to ${me.schoolName ?? 'another school'}.',
      );
    }
    final myOldKey = await signingPublicKey(me.signingSeed);
    final keyChanges = myOldKey != header.rootPublicKey;
    if (keyChanges) {
      final ownElsewhere = [
        for (final c in await _db.classSyncDao.ownedClasses())
          if (c.classKey != null && !classUuids.contains(c.groupUuid)) c,
      ];
      final coTeachElsewhere = [
        for (final d in await _db.coTeacherDao.delegatedClasses())
          if (!classUuids.contains(d.classGroupUuid)) d,
      ];
      if (ownElsewhere.isNotEmpty || coTeachElsewhere.isNotEmpty) {
        return const PromotionResult.failed(
          'This device already teaches other classes',
        );
      }
      // Its key names this device in the progress reports it sends for
      // the classes it joined as a student.
      if ((await _db.classSyncDao.joinedClasses()).isNotEmpty) {
        return const PromotionResult.failed(
          'This device joined classes as a student',
        );
      }
    }

    final generation = [header.generation, me.hostGeneration].reduce(
      (a, b) => a > b ? a : b,
    ) + 1;
    final floor = generationFloor(generation);
    var notes = 0;

    await _db.transaction(() async {
      // 1. Identity: the school's key, a teacher device, one generation up.
      await (_db.update(_db.syncIdentity)..where((t) => t.id.equals(1)))
          .write(
            SyncIdentityCompanion(
              signingSeed: Value(seed),
              schoolId: Value(header.schoolId),
              schoolName: Value(inner['school_name'] as String? ?? ''),
              deviceRole: const Value(kRoleTeacher),
              hostGeneration: Value(generation),
              // Same passphrase, so this device can have a standby too.
              failoverSealKey: Value(ledgerKey),
              failoverKdfSalt: Value(header.salt),
              failoverKdfRounds: Value(header.rounds),
            ),
          );

      // 2. Classes, as owned rows (never `joined`).
      for (final c in classes) {
        final uuid = c['uuid'], name = c['class_name'], key = c['class_key'];
        if (uuid is! String || name is! String || key is! String) continue;
        final values = ClassGroupsCompanion(
          className: Value(name),
          streamName: Value(c['stream_name'] as String?),
          schoolId: Value(header.schoolId),
          classKey: Value(key),
          joined: const Value(false),
          rosterVersion: Value(c['roster_version'] as int?),
          rosterJson: Value(c['roster_json'] as String?),
          ownerTeacherId: Value(ownerTeacherId),
        );
        final existing = await (_db.select(_db.classGroups)
              ..where((t) => t.groupUuid.equals(uuid)))
            .getSingleOrNull();
        if (existing == null) {
          await _db
              .into(_db.classGroups)
              .insert(values.copyWith(groupUuid: Value(uuid)));
        } else {
          await (_db.update(_db.classGroups)
                ..where((t) => t.id.equals(existing.id)))
              .write(values);
        }
        // Was a co-teacher of this class: it's root's now.
        await (_db.delete(_db.coTeachingClasses)
              ..where((t) => t.classGroupUuid.equals(uuid)))
            .go();
      }

      // 3. Channel versions, lifted above everything the old host signed.
      for (final ch in _maps(inner['served_channels'])) {
        final uuid = ch['class_uuid'], subject = ch['subject_id'];
        final version = ch['version'];
        if (uuid is! String || subject is! String || version is! int) continue;
        final lifted = floor + version % kHostGenerationStride;
        final existing = await (_db.select(_db.servedChannels)
              ..where(
                (t) =>
                    t.classGroupUuid.equals(uuid) & t.subjectId.equals(subject),
              ))
            .getSingleOrNull();
        if (existing == null) {
          await _db
              .into(_db.servedChannels)
              .insert(
                ServedChannelsCompanion.insert(
                  classGroupUuid: uuid,
                  subjectId: subject,
                  digest: Value(ch['digest'] as String?),
                  version: lifted,
                ),
              );
        } else if (existing.version < lifted) {
          await (_db.update(_db.servedChannels)
                ..where((t) => t.id.equals(existing.id)))
              .write(
                ServedChannelsCompanion(
                  digest: Value(ch['digest'] as String?),
                  version: Value(lifted),
                ),
              );
        }
      }

      // 4. Co-teachers, minus this device's own former slot.
      for (final r in _maps(inner['co_teachers'])) {
        final uuid = r['class_uuid'], key = r['public_key'];
        final name = r['name'], subjects = r['subject_ids_json'];
        if (uuid is! String ||
            key is! String ||
            name is! String ||
            subjects is! String ||
            key == myOldKey) {
          continue;
        }
        await _db
            .into(_db.classCoTeachers)
            .insert(
              ClassCoTeachersCompanion.insert(
                classGroupUuid: uuid,
                publicKey: key,
                name: name,
                subjectIdsJson: subjects,
              ),
              mode: InsertMode.insertOrReplace,
            );
      }
      if (keyChanges) {
        await (_db.delete(_db.classCoTeachers)
              ..where((t) => t.publicKey.equals(myOldKey)))
            .go();
      }

      // 5. The teacher's subjects, shares and shared notes. Note payloads
      //    are copied field for field, so every chunk hashes to the id
      //    students already hold and an unchanged subject isn't re-sent.
      for (final s in _maps(inner['subjects'])) {
        final id = s['subject_id'], name = s['name'], at = s['created_at'];
        if (id is! String || name is! String || at is! String) continue;
        await _db
            .into(_db.customSubjects)
            .insert(
              CustomSubjectsCompanion.insert(
                subjectId: id,
                name: name,
                icon: Value(s['icon'] as String? ?? 'menu_book'),
                color: Value(s['color'] as String? ?? '#4F46E5'),
                createdAt: at,
                ownerTeacherId: Value(ownerTeacherId),
              ),
              mode: InsertMode.insertOrIgnore,
            );
      }
      for (final sh in _maps(inner['shares'])) {
        final subject = sh['subject_id'], doc = sh['document_title'];
        final uuid = sh['class_uuid'];
        if (subject is! String || doc is! String || uuid is! String) continue;
        await _db
            .into(_db.resourceShares)
            .insert(
              ResourceSharesCompanion.insert(
                subjectId: subject,
                documentTitle: doc,
                classGroupUuid: uuid,
              ),
              mode: InsertMode.insertOrIgnore,
            );
      }
      final have = {
        for (final r in await (_db.select(
          _db.topicResources,
        )..where((t) => t.classGroupUuid.isNull())).get())
          _chunkId(
            r.subjectId,
            r.topicKey,
            r.termMarker,
            r.resourceTitle,
            r.contentChunk,
            r.createdAt,
            r.updatedAt,
            r.documentTitle,
          ),
      };
      for (final n in _maps(inner['notes'])) {
        final subject = n['subject_id'], topic = n['topic_key'];
        final term = n['term_marker'], title = n['resource_title'];
        final content = n['content_chunk'], at = n['created_at'];
        if (subject is! String ||
            topic is! String ||
            term is! int ||
            title is! String ||
            content is! String ||
            at is! String) {
          continue;
        }
        final updated = n['updated_at'] as String?;
        final doc = n['document_title'] as String?;
        if (!have.add(
          _chunkId(subject, topic, term, title, content, at, updated, doc),
        )) {
          continue;
        }
        await _db
            .into(_db.topicResources)
            .insert(
              TopicResourcesCompanion.insert(
                subjectId: subject,
                topicKey: topic,
                termMarker: Value(term),
                resourceTitle: title,
                contentChunk: content,
                createdAt: at,
                updatedAt: Value(updated),
                documentTitle: Value(doc),
              ),
            );
        notes++;
      }

      // 6. Re-sign each roster above the new floor (the old device's
      //    rosters are then older), now that the co-teacher rows are final.
      for (final uuid in classUuids) {
        final group = await _db.classSyncDao.ownedByUuid(uuid);
        if (group == null) continue;
        final hasCoTeachers =
            (await _db.coTeacherDao.coTeachersFor(uuid)).isNotEmpty;
        if (group.rosterJson != null || hasCoTeachers) {
          await _db.coTeacherDao.republishRoster(group);
        }
      }

      // 7. No longer standing by: this device is the host.
      await (_db.delete(_db.hostLedgers)).go();
    });

    stopMirroring();
    return PromotionResult.promoted(
      generation: generation,
      classes: classUuids.length,
      notes: notes,
    );
  }

  static List<Map<String, Object?>> _maps(Object? list) => [
    if (list is List)
      for (final e in list)
        if (e is Map) Map<String, Object?>.from(e),
  ];

  static String _chunkId(
    String subject,
    String topic,
    int term,
    String title,
    String content,
    String createdAt,
    String? updatedAt,
    String? documentTitle,
  ) => ResourceChunkEnvelope.forChannel(
    classGroupUuid: '',
    subjectId: subject,
    topicKey: topic,
    termMarker: term,
    resourceTitle: title,
    contentChunk: content,
    createdAt: createdAt,
    updatedAt: updatedAt,
    documentTitle: documentTitle,
  ).chunkId;

  void dispose() {
    stopMirroring();
    _client.close();
  }
}

/// This root teacher device's host ledger, sealed under its failover
/// passphrase. Null when no passphrase is set or this isn't a teacher
/// device with a school. Used by `ClassShareServer` to answer a standby.
Future<Map<String, dynamic>?> buildSealedLedger(OticDatabase db) async {
  final me = await db.classSyncDao.identity();
  final key = me.failoverSealKey, salt = me.failoverKdfSalt;
  final rounds = me.failoverKdfRounds, schoolId = me.schoolId;
  if (key == null ||
      salt == null ||
      rounds == null ||
      schoolId == null) {
    return null;
  }
  final owned = [
    for (final c in await db.classSyncDao.ownedClasses())
      if (c.classKey != null) c,
  ];
  final uuids = {for (final c in owned) c.groupUuid!};

  final shares = [
    for (final s in await db.select(db.resourceShares).get())
      if (uuids.contains(s.classGroupUuid)) s,
  ];
  // Only notes written here and shared with one of these classes — the
  // same rows ClassSyncDao.sharedChunks serves, nothing private.
  final notes = uuids.isEmpty
      ? const <TopicResource>[]
      : [
          for (final r in await db
              .customSelect(
                'SELECT DISTINCT t.* FROM topic_resources t '
                'JOIN resource_shares s '
                '  ON s.subject_id = t.subject_id '
                '  AND s.document_title = '
                '      COALESCE(t.document_title, t.resource_title) '
                'WHERE t.class_group_uuid IS NULL '
                '  AND s.class_group_uuid IN '
                '      (${List.filled(uuids.length, '?').join(', ')}) '
                'ORDER BY t.id',
                variables: [for (final u in uuids) Variable.withString(u)],
                readsFrom: {db.topicResources, db.resourceShares},
              )
              .get())
            db.topicResources.map(r.data),
        ];

  final inner = <String, Object?>{
    'signing_seed': me.signingSeed,
    'school_id': schoolId,
    'school_name': me.schoolName ?? '',
    'generation': me.hostGeneration,
    'classes': [
      for (final c in owned)
        {
          'uuid': c.groupUuid,
          'class_name': c.className,
          'stream_name': c.streamName,
          'class_key': c.classKey,
          'roster_version': c.rosterVersion,
          'roster_json': c.rosterJson,
        },
    ],
    'served_channels': [
      for (final s in await db.select(db.servedChannels).get())
        if (uuids.contains(s.classGroupUuid))
          {
            'class_uuid': s.classGroupUuid,
            'subject_id': s.subjectId,
            'digest': s.digest,
            'version': s.version,
          },
    ],
    'co_teachers': [
      for (final r in await db.select(db.classCoTeachers).get())
        if (uuids.contains(r.classGroupUuid))
          {
            'class_uuid': r.classGroupUuid,
            'public_key': r.publicKey,
            'name': r.name,
            'subject_ids_json': r.subjectIdsJson,
          },
    ],
    'subjects': [
      for (final s in await db.classSyncDao.ownSubjects())
        {
          'subject_id': s.subjectId,
          'name': s.name,
          'icon': s.icon,
          'color': s.color,
          'created_at': s.createdAt,
        },
    ],
    'shares': [
      for (final s in shares)
        {
          'subject_id': s.subjectId,
          'document_title': s.documentTitle,
          'class_uuid': s.classGroupUuid,
        },
    ],
    'notes': [
      for (final n in notes)
        {
          'subject_id': n.subjectId,
          'topic_key': n.topicKey,
          'term_marker': n.termMarker,
          'resource_title': n.resourceTitle,
          'content_chunk': n.contentChunk,
          'created_at': n.createdAt,
          'updated_at': n.updatedAt,
          'document_title': n.documentTitle,
        },
    ],
  };
  return sealLedger(
    ledgerKey: key,
    salt: salt,
    rounds: rounds,
    schoolId: schoolId,
    rootPublicKey: await signingPublicKey(me.signingSeed),
    generation: me.hostGeneration,
    inner: inner,
  );
}
