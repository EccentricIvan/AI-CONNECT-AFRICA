import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../curriculum/subject_style.dart';
import '../../shared/widgets/studio_page.dart';
import 'subject_notes.dart';

/// A subject's icon in its card colour, so its notes read as that
/// subject's wherever they are listed.
class SubjectBadge extends ConsumerWidget {
  const SubjectBadge({super.key, required this.subjectId, this.size = 34});

  final String subjectId;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(subjectsByIdProvider).valueOrNull?[subjectId];
    final style = s == null
        ? subjectStyleFor(subjectNameFromId(subjectId))
        : (icon: s.icon, color: s.color);
    return StudioIconChip(
      icon: subjectIcon(style.icon),
      color: Color(int.parse(style.color.replaceFirst('#', '0xFF'))),
      size: size,
      radius: size / 3,
    );
  }
}
