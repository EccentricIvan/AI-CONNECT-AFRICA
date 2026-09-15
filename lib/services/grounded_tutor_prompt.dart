/// The hardgrounded prompt frame: teacher's lesson notes in, tutor answer out.
///
/// ## Why this is split in two
///
/// The agreed template is one block containing an instruction, a fact book and
/// the student's question. It is *sent* as one block — [composeGroundedPrompt]
/// reproduces it verbatim — but it is **assembled** from a stable half and a
/// variable half, and the split is load-bearing on this hardware.
///
/// `QwenChatService.warmKvCache` pins the system prompt into LiteRT's KV cache
/// so later turns only prefill the new user tokens; that is the whole reason
/// time-to-first-token is tolerable on a 4 GB phone. A system prompt that
/// changes every turn — which is what embedding the retrieved notes in it would
/// mean — invalidates that pin on every question and throws the optimization
/// away. So the instruction paragraph, which never changes, is the system
/// prompt ([kGroundedTutorSystemPrompt]), and the fact book plus the question,
/// which change every turn, are the user prompt ([buildGroundedUserPrompt]).
///
/// The model sees exactly the same text either way.
library;

/// Stable instruction half — safe to pin, identical on every turn.
const kGroundedTutorSystemPrompt = '''
You are an expert offline classroom tutor. Answer the student's question using ONLY the verified facts from the teacher's lesson notes provided below. If no lesson notes are present or the text does not fully cover the inquiry, rely on established universal scientific and historical facts to generate a concise, world-wide true response.
/no_think
''';

/// Shown in place of the fact book when retrieval came back empty.
///
/// This string is why [OfflineRagService.retrieveContextForQuery] is allowed to
/// return `''` as an ordinary outcome: the absent case is handled here, in the
/// prompt, rather than by a branch at every call site. An empty section would
/// read to the model as "the notes are blank", which is not the same claim as
/// "there are no notes, use what you know".
const kNoCustomNotesFallback =
    'No custom notes uploaded for this topic. Use global core textbook definitions.';

/// Variable half — the fact book and the question, rebuilt each turn.
String buildGroundedUserPrompt({
  required String retrievedDbChunks,
  required String studentQuestion,
}) {
  final factBook = retrievedDbChunks.trim().isNotEmpty
      ? retrievedDbChunks.trim()
      : kNoCustomNotesFallback;
  return '''
[TEACHER'S LESSON NOTES FACT BOOK]:
$factBook

[STUDENT QUESTION]:
${studentQuestion.trim()}
''';
}

/// The complete frame as one block — the agreed template, verbatim.
///
/// Used by callers that hand a model a single string, and by the tests that
/// assert the wording has not drifted. The runtime path sends the same text
/// as system + user rather than as one string; see the library doc above.
String composeGroundedPrompt({
  required String retrievedDbChunks,
  required String studentQuestion,
}) {
  return '${kGroundedTutorSystemPrompt.trim()}\n\n'
      '${buildGroundedUserPrompt(retrievedDbChunks: retrievedDbChunks, studentQuestion: studentQuestion)}';
}
