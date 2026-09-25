import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../db/otic_database.dart';
import '../../features/projects/scaffold/project_scaffold.dart';
import '../../features/website/block_models.dart';
import '../../features/website/html_generator.dart';
import 'project_store.dart';

/// Gives every creation saved as a database row a project folder too:
///
/// * `app_builder_projects` rows from before project folders existed,
/// * `website_projects` (the Block canvas, which still saves rows), and
/// * `student_projects` (the guided Create chat — essays, plans…).
///
/// Each row becomes a folder with the stable id `legacy-<table>-<rowId>`
/// and is refreshed when its row is newer than the folder. Ids already
/// written are remembered in `<learner>/.otic-synced.json`, so a folder the
/// student deletes (in the app or in Explorer) is not brought back.
class LegacyProjectSync {
  LegacyProjectSync(this._db, this._store);

  final OticDatabase _db;
  final ProjectStore _store;

  static const _ledgerName = '.otic-synced.json';

  Future<void> sync(int studentId, {String? studentName}) async {
    try {
      final learner = await _store.learnerDirectory(studentId, studentName: studentName);
      final ledgerFile = File(p.join(learner.path, _ledgerName));
      final synced = <String>{};
      if (await ledgerFile.exists()) {
        try {
          synced.addAll((jsonDecode(await ledgerFile.readAsString()) as List).cast<String>());
        } catch (_) {}
      }
      final existing = {
        for (final f in await _store.list(studentId)) f.manifest.id: f,
      };
      var changed = false;

      Future<void> upsert({
        required String id,
        required DateTime updatedAt,
        required Future<void> Function() write,
      }) async {
        final folder = existing[id];
        if (folder == null && synced.contains(id)) return; // deleted on purpose
        if (folder != null && !updatedAt.isAfter(folder.manifest.updatedAt)) return;
        await write();
        if (synced.add(id)) changed = true;
      }

      for (final row in await _db.appBuilderProjectDao.getProjectsForStudent(studentId)) {
        final id = 'legacy-app-${row.id}';
        await upsert(
          id: id,
          updatedAt: row.updatedAt,
          write: () async {
            final images = <String, Uint8List>{};
            final files = buildAppProject(
              title: row.title,
              html: row.htmlContent,
              appTypeId: row.appTypeId,
              appTypeName: row.appTypeName,
              themeColor: row.themeColor,
              images: images,
            );
            await _store.save(
              studentId: studentId,
              studentName: studentName,
              kind: ProjectKind.application,
              title: row.title,
              files: files,
              binaryFiles: images,
              projectId: id,
              source: 'app_builder',
              template: row.appTypeId,
              templateName: row.appTypeName,
              answers: _answers(row.answersJson),
            );
          },
        );
      }

      for (final row in await _db.websiteDao.getWebsitesForStudent(studentId)) {
        final id = 'legacy-site-${row.id}';
        await upsert(
          id: id,
          updatedAt: row.updatedAt,
          write: () async {
            final doc = WebsiteDoc(
              title: row.title,
              themeColor: row.themeColor,
              blocks: WebsiteDoc.blocksFromJson(row.blocksJson),
            );
            final images = <String, Uint8List>{};
            final files = buildWebsiteProject(
              title: row.title,
              html: generateHtml(doc),
              templateName: 'Block canvas',
              images: images,
            );
            await _store.save(
              studentId: studentId,
              studentName: studentName,
              kind: ProjectKind.website,
              title: row.title,
              files: files,
              binaryFiles: images,
              projectId: id,
              source: 'block_canvas',
            );
          },
        );
      }

      for (final row in await _db.projectDao.getProjectsForStudent(studentId)) {
        final id = 'legacy-guided-${row.id}';
        await upsert(
          id: id,
          updatedAt: row.updatedAt,
          write: () async {
            final steps = <({String role, String text})>[];
            try {
              for (final s in jsonDecode(row.stepsJson) as List) {
                final m = s as Map;
                steps.add((role: '${m['role']}', text: '${m['text']}'));
              }
            } catch (_) {}
            await _store.save(
              studentId: studentId,
              studentName: studentName,
              kind: ProjectKind.guided,
              title: row.title,
              files: buildGuidedProject(
                title: row.title,
                projectType: row.projectType,
                topic: row.topic,
                steps: steps,
              ),
              projectId: id,
              source: 'guided',
              template: row.projectType,
            );
          },
        );
      }

      if (changed) {
        await ledgerFile.writeAsString(jsonEncode(synced.toList()..sort()));
      }
    } catch (e, st) {
      // Listing projects must never fail because an old row is odd.
      debugPrint('LegacyProjectSync failed: $e\n$st');
    }
  }

  static Map<String, String> _answers(String json) {
    try {
      return {
        for (final e in (jsonDecode(json) as Map).entries) '${e.key}': '${e.value}',
      };
    } catch (_) {
      return const {};
    }
  }
}
