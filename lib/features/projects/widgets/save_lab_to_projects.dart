import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_locale.dart';
import '../../../services/projects/project_providers.dart';

/// "Save to Projects" for the code labs: asks for a name the first time,
/// then keeps saving into the same folder. Returns the saved project's id
/// and title (pass them back next time), or null when nothing was saved.
Future<({String id, String title})?> saveLabToProjects(
  BuildContext context,
  WidgetRef ref, {
  required ProjectKind kind,
  required String suggestedTitle,
  required Map<String, String> Function(String title, Map<String, Uint8List> images) buildFiles,
  required String source,
  String? projectId,
  String? currentTitle,
}) async {
  var title = currentTitle;
  if (title == null) {
    final controller = TextEditingController(text: suggestedTitle);
    title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(ctx, 'Save to Projects')),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 60,
          decoration: InputDecoration(labelText: tr(ctx, 'Project name')),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr(ctx, 'Cancel'))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(tr(ctx, 'Save')),
          ),
        ],
      ),
    );
    if (title == null || title.trim().isEmpty) return null;
    title = title.trim();
  }
  try {
    final images = <String, Uint8List>{};
    final files = buildFiles(title, images);
    final saved = await saveCreation(
      ref,
      kind: kind,
      title: title,
      files: files,
      binaryFiles: images,
      projectId: projectId,
      source: source,
    );
    final result = saved == null ? null : (id: saved.folder.manifest.id, title: title);
    if (!context.mounted) return result;
    if (saved == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr(context, 'Create a learner profile to save projects.'))));
      return null;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(trFill(context, 'Saved “{name}” to Projects', {'name': saved.breadcrumb})),
      action: SnackBarAction(
        label: tr(context, 'Open'),
        onPressed: () => context.push('/projects'),
      ),
    ));
    return result;
  } catch (e) {
    debugPrint('lab save failed: $e');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr(context, "Couldn't save your project. Try again."))));
    }
    return null;
  }
}
