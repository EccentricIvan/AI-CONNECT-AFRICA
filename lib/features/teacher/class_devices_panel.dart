import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../collaboration/sync/device_registry.dart';
import '../../core/policy/policy.dart';
import '../../core/theme/app_colors.dart';
import '../../db/otic_database.dart';
import '../../db/providers/db_provider.dart';
import '../../shared/widgets/studio_page.dart';
import 'class_providers.dart';
import 'teacher_profiles.dart';

final _membersProvider = StreamProvider.autoDispose
    .family<List<ClassMember>, String>(
      (ref, classUuid) =>
          DeviceRegistry(ref.watch(dbProvider)).watchMembers(classUuid),
    );

/// The devices that joined one class, with Revoke. A revoked device is
/// refused from then on and the class key is replaced.
class ClassDevicesPanel extends ConsumerWidget {
  const ClassDevicesPanel({super.key, required this.group});

  final ClassGroup group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ac = AppColors.of(context);
    final uuid = group.groupUuid;
    final members = uuid == null
        ? const <ClassMember>[]
        : ref.watch(_membersProvider(uuid)).valueOrNull ?? const [];

    return StudioCard(
      accent: AppColors.accentCyan,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Devices · ${classLabel(group)}',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: ac.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          if (members.isEmpty)
            Text('None yet', style: TextStyle(color: ac.textSecondary)),
          for (final m in members)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: Icon(
                m.revokedAt == null
                    ? Icons.devices_rounded
                    : Icons.block_rounded,
                color: m.revokedAt == null ? ac.textSecondary : Colors.red,
              ),
              title: Text(m.name.isEmpty ? 'Device' : m.name),
              subtitle: Text(
                m.revokedAt != null
                    ? 'Revoked'
                    : 'Last sync ${_day(m.lastSeenAt ?? m.joinedAt)}'
                          '${m.boxKey == null ? ' · older app' : ''}',
              ),
              trailing: m.revokedAt != null
                  ? null
                  : TextButton(
                      onPressed: () => _revoke(context, ref, m),
                      child: const Text('Revoke'),
                    ),
            ),
        ],
      ),
    );
  }

  static String _day(String iso) =>
      iso.length >= 10 ? iso.substring(0, 10) : iso;

  Future<void> _revoke(
    BuildContext context,
    WidgetRef ref,
    ClassMember m,
  ) async {
    final allowed = await ref
        .read(policyProvider)
        .can(
          TeacherActor(ref.read(activeTeacherIdProvider)),
          ManageClassDevices(m.classGroupUuid),
        );
    if (!context.mounted) return;
    if (!allowed) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Not your class')));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Revoke ${m.name.isEmpty ? 'this device' : m.name}?'),
        content: const Text('It gets nothing from this class again.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final mustRejoin = await DeviceRegistry(
      ref.read(dbProvider),
    ).revoke(m.classGroupUuid, m.deviceKey);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          mustRejoin == 0
              ? 'Revoked'
              : 'Revoked · $mustRejoin device${mustRejoin == 1 ? '' : 's'} '
                    'on an older app must join again',
        ),
      ),
    );
  }
}
