import 'dart:convert';

import 'package:drift/drift.dart';

import '../../db/otic_database.dart';
import 'class_crypto.dart';
import 'device_keys.dart';

/// Which devices hold a class, and which are refused.
///
/// A device names itself on every request with its Ed25519 key
/// ([kDeviceHeader]). The teacher's device records each one per class
/// ([ClassMembers]); revoking one marks it and replaces the class key, so
/// the old key opens nothing sent afterwards. Devices still trusted get the
/// new key sealed to their X25519 box key on their next sync. A device on
/// an older build has no box key and must join again.
///
/// The Admin can also revoke a device for the whole school
/// ([RevokedDevices]); that list travels in the Admin's records, and each
/// teacher's device then revokes it in every class it holds.
class DeviceRegistry {
  DeviceRegistry(this._db);

  final OticDatabase _db;

  static String _now() => DateTime.now().toUtc().toIso8601String();

  // ── This device ──────────────────────────────────────────────────────

  /// This device's X25519 seed, made the first time it's needed.
  Future<String> boxSeed() async {
    final me = await _db.classSyncDao.identity();
    final seed = me.boxSeed;
    if (seed != null) return seed;
    final fresh = newBoxSeed();
    await (_db.update(_db.syncIdentity)
          ..where((t) => t.id.equals(1) & t.boxSeed.isNull()))
        .write(SyncIdentityCompanion(boxSeed: Value(fresh)));
    return (await _db.classSyncDao.identity()).boxSeed!;
  }

  /// What a joining device sends: its signing and box public keys.
  Future<Map<String, String>> myKeys() async {
    final me = await _db.classSyncDao.identity();
    return {
      'device_key': await signingPublicKey(me.signingSeed),
      'box_key': await boxPublicKey(await boxSeed()),
    };
  }

  /// Headers naming and signing one request as this device.
  Future<Map<String, String>> requestHeaders({
    required String path,
    required String nonce,
    required String body,
  }) async {
    final me = await _db.classSyncDao.identity();
    return {
      kDeviceHeader: await signingPublicKey(me.signingSeed),
      kDeviceSigHeader: await signDeviceRequest(
        signingSeed: me.signingSeed,
        path: path,
        nonce: nonce,
        body: body,
      ),
    };
  }

  // ── A class's devices (teacher side) ─────────────────────────────────

  Future<ClassMember?> member(String classUuid, String deviceKey) =>
      (_db.select(_db.classMembers)
            ..where((t) => t.classGroupUuid.equals(classUuid))
            ..where((t) => t.deviceKey.equals(deviceKey)))
          .getSingleOrNull();

  Stream<List<ClassMember>> watchMembers(String classUuid) =>
      (_db.select(_db.classMembers)
            ..where((t) => t.classGroupUuid.equals(classUuid))
            ..orderBy([
              (t) => OrderingTerm.asc(t.revokedAt.isNotNull()),
              (t) => OrderingTerm.asc(t.name),
            ]))
          .watch();

  /// Records a device that joined [classUuid], or that a request just
  /// came from. Never clears a revocation; fills in a box key or name it
  /// didn't have.
  Future<void> recordMember(
    String classUuid,
    String deviceKey, {
    String? boxKey,
    String? name,
  }) async {
    final existing = await member(classUuid, deviceKey);
    final cleanName = name?.trim();
    if (existing == null) {
      await _db
          .into(_db.classMembers)
          .insert(
            ClassMembersCompanion.insert(
              classGroupUuid: classUuid,
              deviceKey: deviceKey,
              boxKey: Value(boxKey),
              name: Value(cleanName ?? ''),
              joinedAt: _now(),
              lastSeenAt: Value(_now()),
            ),
          );
      return;
    }
    await (_db.update(
      _db.classMembers,
    )..where((t) => t.id.equals(existing.id))).write(
      ClassMembersCompanion(
        lastSeenAt: Value(_now()),
        boxKey: boxKey == null ? const Value.absent() : Value(boxKey),
        name: cleanName == null || cleanName.isEmpty
            ? const Value.absent()
            : Value(cleanName),
      ),
    );
  }

  /// Whether [deviceKey] is refused for [classUuid]: revoked in that class,
  /// or for the whole school.
  Future<bool> isRevoked(String classUuid, String deviceKey) async {
    final m = await member(classUuid, deviceKey);
    if (m?.revokedAt != null) return true;
    return await (_db.select(
          _db.revokedDevices,
        )..where((t) => t.deviceKey.equals(deviceKey))).getSingleOrNull() !=
        null;
  }

  /// Revokes [deviceKey] in [classUuid] and replaces the class key. Returns
  /// how many devices still in the class are on an older build and must
  /// join again to get the new key.
  Future<int> revoke(String classUuid, String deviceKey) =>
      _db.transaction(() async {
        final group = await _db.classGroupDao.findByUuid(classUuid);
        if (group == null || group.joined) return 0;
        final m = await member(classUuid, deviceKey);
        if (m == null) {
          await _db
              .into(_db.classMembers)
              .insert(
                ClassMembersCompanion.insert(
                  classGroupUuid: classUuid,
                  deviceKey: deviceKey,
                  joinedAt: _now(),
                  revokedAt: Value(_now()),
                ),
              );
        } else if (m.revokedAt == null) {
          await (_db.update(_db.classMembers)..where((t) => t.id.equals(m.id)))
              .write(ClassMembersCompanion(revokedAt: Value(_now())));
        }
        await _rotateKey(group);
        return (await (_db.select(_db.classMembers)
                  ..where((t) => t.classGroupUuid.equals(classUuid))
                  ..where((t) => t.revokedAt.isNull())
                  ..where((t) => t.boxKey.isNull()))
                .get())
            .length;
      });

  /// Gives [group] a new class key and keeps the old one as retired, so a
  /// trusted device still holding it can ask for the new one.
  Future<void> _rotateKey(ClassGroup group) async {
    final old = group.classKey;
    if (old == null) return;
    final retired = [...retiredKeysOf(group), old];
    await (_db.update(
      _db.classGroups,
    )..where((t) => t.id.equals(group.id))).write(
      ClassGroupsCompanion(
        classKey: Value(newClassKey()),
        retiredKeysJson: Value(jsonEncode(retired)),
      ),
    );
  }

  static List<String> retiredKeysOf(ClassGroup group) {
    final raw = group.retiredKeysJson;
    if (raw == null) return const [];
    try {
      return [
        for (final k in jsonDecode(raw) as List)
          if (k is String) k,
      ];
    } catch (_) {
      return const [];
    }
  }

  // ── The whole school (Admin) ─────────────────────────────────────────

  Stream<List<RevokedDevice>> watchRevoked() =>
      _db.select(_db.revokedDevices).watch();

  /// Revokes [deviceKey] for the whole school: refused by every Sync on
  /// this device, and revoked in every class this device holds it in.
  /// Other devices take it from the Admin's records.
  Future<void> revokeSchoolWide(String deviceKey, {String name = ''}) async {
    await _db
        .into(_db.revokedDevices)
        .insertOnConflictUpdate(
          RevokedDevicesCompanion.insert(
            deviceKey: deviceKey,
            name: Value(name),
            revokedAt: _now(),
          ),
        );
    await applySchoolRevocations();
  }

  /// Revokes, in this device's own classes, every device the school has
  /// revoked that is still trusted here.
  Future<void> applySchoolRevocations() async {
    final revoked = {
      for (final r in await _db.select(_db.revokedDevices).get()) r.deviceKey,
    };
    if (revoked.isEmpty) return;
    final trusted = await (_db.select(
      _db.classMembers,
    )..where((t) => t.revokedAt.isNull())).get();
    for (final m in trusted) {
      if (revoked.contains(m.deviceKey)) {
        await revoke(m.classGroupUuid, m.deviceKey);
      }
    }
  }

  /// Admin side: a device that took the school's records.
  Future<void> registerSchoolDevice(String deviceKey, String name) => _db
      .into(_db.schoolDevices)
      .insertOnConflictUpdate(
        SchoolDevicesCompanion.insert(
          deviceKey: deviceKey,
          name: Value(name),
          registeredAt: _now(),
        ),
      );

  Stream<List<SchoolDevice>> watchSchoolDevices() => (_db.select(
    _db.schoolDevices,
  )..orderBy([(t) => OrderingTerm.asc(t.name)])).watch();
}
