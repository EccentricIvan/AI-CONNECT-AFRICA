import 'dart:io';

import 'package:flutter/material.dart';

import '../../l10n/app_locale.dart';
import '../../services/projects/project_store.dart';
import 'project_actions.dart';

const _textExtensions = {
  'html', 'css', 'js', 'json', 'py', 'md', 'txt', 'yaml', 'yml', 'toml', 'ini',
  'svg', 'webmanifest', 'gitignore', 'dockerignore', 'example', 'dart', 'env',
};

bool _isText(String rel) {
  final name = rel.split('/').last.toLowerCase();
  if (name == 'dockerfile') return true;
  final ext = name.contains('.') ? name.split('.').last : name;
  return _textExtensions.contains(ext);
}

IconData _iconFor(String rel) {
  final ext = rel.split('.').last.toLowerCase();
  return switch (ext) {
    'html' => Icons.html_rounded,
    'css' => Icons.palette_outlined,
    'js' => Icons.javascript_rounded,
    'py' => Icons.code_rounded,
    'md' => Icons.description_outlined,
    'png' || 'jpg' || 'jpeg' || 'gif' || 'webp' => Icons.image_outlined,
    'json' || 'yaml' || 'yml' || 'ini' || 'toml' => Icons.settings_outlined,
    _ => Icons.insert_drive_file_outlined,
  };
}

/// Read-only browser for a project's files; tap one to read it and copy it.
/// [initialPrefix] (e.g. `backend/`) lists that part first.
Future<void> showProjectFilesSheet(
  BuildContext context,
  ProjectFolder folder, {
  String initialPrefix = '',
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      builder: (ctx, scroll) => _FilesList(
        folder: folder,
        initialPrefix: initialPrefix,
        scroll: scroll,
      ),
    ),
  );
}

class _FilesList extends StatelessWidget {
  const _FilesList({required this.folder, required this.initialPrefix, required this.scroll});
  final ProjectFolder folder;
  final String initialPrefix;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<(String, File)>>(
      future: ProjectStore().files(folder),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final all = snap.data!
            .where((e) => e.$1 != ProjectManifest.fileName)
            .toList()
          ..sort((a, b) {
            final ap = a.$1.startsWith(initialPrefix) ? 0 : 1;
            final bp = b.$1.startsWith(initialPrefix) ? 0 : 1;
            return ap != bp ? ap - bp : a.$1.compareTo(b.$1);
          });
        return ListView.builder(
          controller: scroll,
          itemCount: all.length + 1,
          itemBuilder: (_, i) {
            if (i == 0) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  trFill(context, '{title} · {n} files',
                      {'title': folder.title, 'n': '${all.length}'}),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              );
            }
            final (rel, file) = all[i - 1];
            return ListTile(
              dense: true,
              leading: Icon(_iconFor(rel), size: 20),
              title: Text(rel, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
              onTap: _isText(rel)
                  ? () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => _FileViewer(rel: rel, file: file),
                      ))
                  : null,
            );
          },
        );
      },
    );
  }
}

class _FileViewer extends StatelessWidget {
  const _FileViewer({required this.rel, required this.file});
  final String rel;
  final File file;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: file.readAsString(),
      builder: (context, snap) {
        final text = snap.data ?? '';
        return Scaffold(
          appBar: AppBar(
            title: Text(rel, style: const TextStyle(fontFamily: 'monospace', fontSize: 14)),
            actions: [
              IconButton(
                tooltip: tr(context, 'Copy'),
                icon: const Icon(Icons.copy_rounded),
                onPressed: snap.hasData ? () => copyTextToClipboard(context, text) : null,
              ),
            ],
          ),
          body: !snap.hasData
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(
                    text,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.45),
                  ),
                ),
        );
      },
    );
  }
}
