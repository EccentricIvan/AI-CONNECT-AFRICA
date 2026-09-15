import 'package:flutter/widgets.dart';

import '../../db/tables/topic_resources_table.dart';
import '../../l10n/app_locale.dart';

/// Teacher-facing wording for the lesson-resource workspace.
///
/// ## The rule these constants exist to enforce
///
/// Nothing in this surface may name the machinery. A teacher adding notes for
/// Senior 4 Chemistry is not choosing a storage engine, and words like
/// *SQLite*, *database*, *JSON*, *chunking*, *embedding*, *vector*, *index* or
/// *token* describe our problems, not theirs. Every string a teacher can read
/// lives in this file, so the rule is reviewable in one place instead of being
/// re-litigated in each widget — and [kForbiddenTechnicalTerms] lets a test
/// assert it mechanically.
///
/// Each value is also a `tr()` key. Rows for the East African languages go in
/// the `kUiStrings*` tables the same way the rest of the app's chrome does;
/// until they exist these render in English, which is the normal fallback
/// behaviour and not a bug.
class ResourceLabels {
  const ResourceLabels._();

  // ── Actions ──────────────────────────────────────────────────────────
  static const addNote = 'Add Lesson Note';
  static const removeResource = 'Remove Resource Material';
  static const termTracker = 'Term Core Tracker';

  // ── Subjects a teacher creates ───────────────────────────────────────
  static const workspace = 'Lesson Materials';
  static const workspaceSubtitle = 'Your subjects and teaching notes';
  static const newSubject = 'New Subject';
  static const subjectName = 'Subject name';
  static const subjectNameHint = 'e.g. Senior 4 Chemistry';
  static const createSubject = 'Create subject';
  static const removeSubject = 'Remove subject';
  static const removeSubjectConfirm =
      'Remove this subject and everything in it?';
  static const mySubjects = 'My subjects';
  static const noSubjects = 'No subjects yet';
  static const noSubjectsHint =
      'Create a subject, then add the notes you teach from.';
  static const subjectCreated = 'Subject created';
  static const subjectRemoved = 'Subject removed';

  // ── Uploading ────────────────────────────────────────────────────────
  static const uploadFile = 'Upload a file';
  static const typeNotes = 'Type notes instead';
  static const uploadHint =
      'PDF, Word, or a text file. Everything stays on this device.';
  static const reading = 'Reading your file…';
  static const readFailed = 'That file could not be used';
  static const importedTopics = 'Sorted into {count} topics';
  static const importedOneTopic = 'Saved as one topic';

  // ── Supporting copy ──────────────────────────────────────────────────
  static const noteTitle = 'Note title';
  static const noteTitleHint = 'e.g. Acid-Base Balances Notes';
  static const noteContent = 'Lesson material';
  static const noteContentHint = 'Type or paste the lesson text here';
  static const chooseSubject = 'Subject';
  static const chooseTopic = 'Topic';
  static const chooseTerm = 'Term';
  static const allTerms = 'All terms';
  static const term1 = 'Term 1';
  static const term2 = 'Term 2';
  static const term3 = 'Term 3';

  static const saveNote = 'Save note';
  static const cancel = 'Cancel';
  static const noResources = 'No lesson notes added yet';
  static const noResourcesHint =
      'Notes you add here are used to answer your students questions on this topic.';
  static const noteSaved = 'Lesson note saved';
  static const noteRemoved = 'Resource material removed';
  static const nothingToRemove = 'That material was not found';
  static const removeConfirm = 'Remove this material for every student?';
  static const usingTeacherNotes = 'Answered from your lesson notes';

  /// Teacher-facing description of a resource's size.
  ///
  /// Reports the material's length in words. The row count is the unit we
  /// store in and is meaningless to a teacher — showing "12 chunks" would leak
  /// exactly the implementation detail this file exists to hide.
  static String materialLength(BuildContext context, int words) {
    return trFill(context, '{count} words', {'count': '$words'});
  }

  /// Label for a `term_marker` value.
  static String termLabel(BuildContext context, int marker) {
    switch (marker) {
      case 1:
        return tr(context, term1);
      case 2:
        return tr(context, term2);
      case 3:
        return tr(context, term3);
      default:
        return tr(context, allTerms);
    }
  }

  /// Every term option, in the order a teacher picks from.
  static const termOptions = kTermMarkers;
}

/// Words that must never appear in teacher-facing copy.
///
/// Asserted over [ResourceLabels] by `test/resource_labels_test.dart`, so a
/// future label mentioning "database" fails the build rather than shipping.
const kForbiddenTechnicalTerms = <String>[
  'sqlite',
  'sql',
  'database',
  'db',
  'table',
  'row',
  'schema',
  'query',
  'json',
  'chunk',
  'chunking',
  'embedding',
  'vector',
  'index',
  'token',
  'rag',
  'retrieval',
  'drift',
];
