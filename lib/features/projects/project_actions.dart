import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../db/providers/db_provider.dart';
import '../../gamification/badge_service.dart';
import '../../l10n/app_locale.dart';
import '../../services/projects/project_providers.dart';

bool get _desktop =>
    !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

void _snack(BuildContext context, String text, {SnackBarAction? action}) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), action: action));
}

Future<void> _afterExport(WidgetRef ref, ProjectFolder folder) async {
  final store = ref.read(projectStoreProvider);
  await store.markExported(folder);
  final student = await ref.read(activeStudentProvider.future);
  if (student != null) {
    await ref.read(badgeServiceProvider).onProjectExported(student.id);
    ref.invalidate(studentProjectFoldersProvider(student.id));
  }
}

/// Desktop: copies the real folder to a place the student picks (a USB
/// stick, their VS Code workspace). Returns the new path.
Future<String?> copyProjectTo(BuildContext context, WidgetRef ref, ProjectFolder folder) async {
  final dest = await FilePicker.platform.getDirectoryPath(
    dialogTitle: tr(context, 'Choose where to copy the project'),
  );
  if (dest == null || !context.mounted) return null;
  try {
    final out = await ref.read(projectStoreProvider).exportToDirectory(folder, dest);
    await _afterExport(ref, folder);
    if (context.mounted) {
      _snack(context, trFill(context, 'Copied to {path}', {'path': out}),
          action: SnackBarAction(
            label: tr(context, 'Show'),
            onPressed: () => showInFileManager(out),
          ));
    }
    return out;
  } catch (e) {
    debugPrint('copy project failed: $e');
    if (context.mounted) _snack(context, tr(context, "Couldn't copy the project. Try again."));
    return null;
  }
}

/// Every platform: saves `<project>.zip` through the system save dialog
/// (Downloads, SD card, Drive…). Returns true when a file was written.
Future<bool> exportProjectZip(BuildContext context, WidgetRef ref, ProjectFolder folder) async {
  try {
    final bytes = await ref.read(projectStoreProvider).exportZip(folder);
    if (!context.mounted) return false;
    final path = await FilePicker.platform.saveFile(
      dialogTitle: tr(context, 'Export project'),
      fileName: '${folder.folderName}.zip',
      type: FileType.custom,
      allowedExtensions: const ['zip'],
      bytes: bytes,
    );
    if (path == null) return false;
    // On desktop saveFile only returns the chosen path; Android wrote it.
    if (_desktop) await File(path).writeAsBytes(bytes);
    await _afterExport(ref, folder);
    if (context.mounted) {
      _snack(context, trFill(context, 'Saved to {path}', {'path': path}));
    }
    return true;
  } catch (e) {
    debugPrint('zip export failed: $e');
    if (context.mounted) _snack(context, tr(context, "Couldn't export the project. Try again."));
    return false;
  }
}

/// Every platform: hands the zip to the share sheet (WhatsApp, Bluetooth,
/// Nearby Share, email…).
Future<bool> shareProjectZip(BuildContext context, WidgetRef ref, ProjectFolder folder) async {
  try {
    final bytes = await ref.read(projectStoreProvider).exportZip(folder);
    final tmp = Directory.systemTemp.createTempSync('otic_share');
    final file = File(p.join(tmp.path, '${folder.folderName}.zip'));
    await file.writeAsBytes(bytes);
    final result = await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], subject: folder.title),
    );
    if (result.status == ShareResultStatus.dismissed) return false;
    await _afterExport(ref, folder);
    return true;
  } catch (e) {
    debugPrint('share project failed: $e');
    if (context.mounted) _snack(context, tr(context, "Couldn't share the project. Try again."));
    return false;
  }
}

/// Windows Explorer / Linux file manager at [path].
Future<void> showInFileManager(String path) async {
  try {
    if (Platform.isWindows) {
      await Process.run('explorer', [path]);
    } else if (Platform.isMacOS) {
      await Process.run('open', [path]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [path]);
    }
  } catch (e) {
    debugPrint('open folder failed: $e');
  }
}

/// True when VS Code's `code` command is on PATH (desktop only).
final vsCodeAvailableProvider = FutureProvider<bool>((ref) async {
  if (!_desktop) return false;
  try {
    final r = await Process.run(Platform.isWindows ? 'where' : 'which', ['code'],
        runInShell: true);
    return r.exitCode == 0;
  } catch (_) {
    return false;
  }
});

Future<void> openInVsCode(BuildContext context, String path) async {
  try {
    await Process.start('code', [path], runInShell: true, mode: ProcessStartMode.detached);
  } catch (e) {
    debugPrint('open in VS Code failed: $e');
    if (context.mounted) _snack(context, tr(context, "Couldn't open VS Code."));
  }
}

Future<void> copyTextToClipboard(BuildContext context, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) _snack(context, tr(context, 'Copied.'));
}
