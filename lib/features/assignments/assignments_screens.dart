import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../db/otic_database.dart';
import '../../db/providers/db_provider.dart';
import '../../services/assignments/class_assignments.dart';
import '../../shared/widgets/responsive.dart';
import '../../shared/widgets/studio_page.dart';
import '../learn/subject_notes.dart';
import '../teacher/teacher_profiles.dart';
import '../teacher/teaching_scope.dart';

final _visibleAssignmentsProvider =
    FutureProvider.autoDispose<List<ClassAssignment>>((ref) async {
      final classUuid = await ref.watch(learnerClassUuidProvider.future);
      return ref.watch(classAssignmentsProvider).visible(classUuid);
    });

final _mySubmissionsProvider = StreamProvider.autoDispose
    .family<List<AssignmentSubmission>, int>(
      (ref, studentId) =>
          ref.watch(classAssignmentsProvider).watchMine(studentId),
    );

/// The active learner's assignments: answer them, then see the grade and
/// the teacher's feedback once their device has synced with the teacher.
class AssignmentsScreen extends ConsumerWidget {
  const AssignmentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final student = ref.watch(activeStudentProvider).valueOrNull;
    final assignments =
        ref.watch(_visibleAssignmentsProvider).valueOrNull ??
        const <ClassAssignment>[];
    final mine = student == null
        ? const <AssignmentSubmission>[]
        : ref.watch(_mySubmissionsProvider(student.id)).valueOrNull ??
              const <AssignmentSubmission>[];
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: const StudioAppBar(
        title: 'Assignments',
        subtitle: 'From your teachers',
        icon: Icons.assignment_rounded,
      ),
      body: MaxWidth(
        maxWidth: 800,
        child: assignments.isEmpty
            ? const Center(child: Text('No assignments'))
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  for (final a in assignments)
                    _AssignmentCard(
                      assignment: a,
                      latest: mine
                          .where((s) => s.assignmentId == a.id)
                          .firstOrNull,
                      onAnswer: student == null
                          ? null
                          : () => _answer(context, ref, student, a),
                    ),
                ],
              ),
      ),
    );
  }

  Future<void> _answer(
    BuildContext context,
    WidgetRef ref,
    Student student,
    ClassAssignment a,
  ) async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(a.title),
        content: SizedBox(
          width: 480,
          child: TextField(
            controller: controller,
            autofocus: true,
            minLines: 6,
            maxLines: 14,
            maxLength: kMaxAnswerChars,
            decoration: const InputDecoration(labelText: 'Your answer'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    final text = controller.text;
    controller.dispose();
    if (ok != true) return;
    await ref
        .read(classAssignmentsProvider)
        .submit(
          student: student,
          assignment: a,
          answer: text,
          memberKey: 'local/${student.id}',
        );
  }
}

class _AssignmentCard extends StatelessWidget {
  const _AssignmentCard({
    required this.assignment,
    required this.latest,
    required this.onAnswer,
  });

  final ClassAssignment assignment;
  final AssignmentSubmission? latest;
  final VoidCallback? onAnswer;

  @override
  Widget build(BuildContext context) {
    final s = latest;
    final status = s == null
        ? 'Not submitted'
        : s.grade != null
        ? 'Grade ${s.grade}/${assignment.maxPoints}'
        : s.receivedAt != null
        ? 'Submitted · with your teacher'
        : 'Submitted · sends at your next Sync';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              assignment.title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (assignment.due != null) Text('Due ${assignment.due}'),
            if (assignment.instructions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(assignment.instructions),
              ),
            const SizedBox(height: 8),
            Text(status, style: const TextStyle(fontWeight: FontWeight.w600)),
            if (s?.feedback case final f?)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Feedback: $f'),
              ),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: onAnswer,
              child: Text(s == null ? 'Answer' : 'Answer again'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Teacher ───────────────────────────────────────────────────────────────

final _gradableProvider = FutureProvider.autoDispose<List<ClassAssignment>>((
  ref,
) async {
  final me = ref.watch(activeTeacherIdProvider);
  if (me == null) return const [];
  final scope = ref.watch(teachingScopeProvider);
  final out = <ClassAssignment>[];
  for (final a in await ref.watch(classAssignmentsProvider).own()) {
    if (await scope.mayChangeNote(me, a.subjectId, a.documentTitle)) {
      out.add(a);
    }
  }
  return out;
});

final _submissionsProvider = StreamProvider.autoDispose
    .family<List<AssignmentSubmission>, String>(
      (ref, assignmentId) =>
          ref.watch(classAssignmentsProvider).watchSubmissions(assignmentId),
    );

/// Teacher → Assignments: the answers to the signed-in teacher's
/// assignments, to grade. Grades reach each learner at their next Sync.
class GradeAssignmentsScreen extends ConsumerWidget {
  const GradeAssignmentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assignments =
        ref.watch(_gradableProvider).valueOrNull ?? const <ClassAssignment>[];
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: const StudioAppBar(
        title: 'Assignments',
        subtitle: 'Grade answers',
        icon: Icons.assignment_turned_in_rounded,
        showBack: true,
      ),
      body: MaxWidth(
        maxWidth: 900,
        child: assignments.isEmpty
            ? const Center(
                child: Text('No assignments — add one in Lesson materials'),
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  for (final a in assignments) _Gradebook(assignment: a),
                ],
              ),
      ),
    );
  }
}

class _Gradebook extends ConsumerWidget {
  const _Gradebook({required this.assignment});
  final ClassAssignment assignment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subs =
        ref.watch(_submissionsProvider(assignment.id)).valueOrNull ??
        const <AssignmentSubmission>[];
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        title: Text(assignment.title),
        subtitle: Text('${subs.length} answers'),
        children: [
          for (final s in subs)
            ListTile(
              title: Text(s.learnerName),
              subtitle: Text(
                s.answer,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Text(
                s.grade == null
                    ? 'Grade'
                    : '${s.grade}/${assignment.maxPoints}',
              ),
              onTap: () => _grade(context, ref, s),
            ),
        ],
      ),
    );
  }

  Future<void> _grade(
    BuildContext context,
    WidgetRef ref,
    AssignmentSubmission s,
  ) async {
    final grade = TextEditingController(text: s.grade?.toString() ?? '');
    final feedback = TextEditingController(text: s.feedback ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.learnerName),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(s.answer),
                TextField(
                  controller: grade,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Grade (out of ${assignment.maxPoints})',
                  ),
                ),
                TextField(
                  controller: feedback,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Feedback'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final value = int.tryParse(grade.text.trim());
    final note = feedback.text;
    grade.dispose();
    feedback.dispose();
    if (ok != true || value == null) return;
    await ref
        .read(classAssignmentsProvider)
        .grade(s.uuid, value.clamp(0, assignment.maxPoints), note);
  }
}

/// Lesson materials → New assignment, for [subjectId].
Future<String?> showNewAssignmentDialog(
  BuildContext context,
  WidgetRef ref,
  String subjectId,
) async {
  final title = TextEditingController();
  final instructions = TextEditingController();
  final points = TextEditingController(text: '10');
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('New assignment'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: title,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            TextField(
              controller: instructions,
              minLines: 3,
              maxLines: 8,
              decoration: const InputDecoration(labelText: 'Instructions'),
            ),
            TextField(
              controller: points,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Points'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Create'),
        ),
      ],
    ),
  );
  final (t, i, p) = (title.text, instructions.text, int.tryParse(points.text));
  title.dispose();
  instructions.dispose();
  points.dispose();
  if (ok != true || p == null) return null;
  return ref
      .read(classAssignmentsProvider)
      .create(subjectId: subjectId, title: t, instructions: i, maxPoints: p);
}
