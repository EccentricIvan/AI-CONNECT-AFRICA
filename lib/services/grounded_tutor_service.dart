import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ai_core/inference/runtime_config.dart';
import 'offline_rag_service.dart';
import 'qwen_chat_service.dart';

/// Joins the two halves of the retrieval path: look up the teacher's notes,
/// then ask the chat brain the grounded question.
///
/// This exists so the lookup happens in exactly one place. Retrieval that is
/// re-implemented at each call site is how the write path and the read path end
/// up spelling `subject_id` differently, which fails silently and forever —
/// see the normalization note in `offline_storage_service.dart`.
class GroundedTutorService {
  const GroundedTutorService(this._rag, this._chat);

  final OfflineRagService _rag;
  final QwenChatService _chat;

  /// Retrieves context for [studentQuestion] and streams the grounded answer.
  ///
  /// Returns a stream of English tokens — the same contract as
  /// [QwenChatService.streamAnswer], so an existing translation layer wraps
  /// this unchanged.
  Stream<String> streamAnswer({
    required String studentQuestion,
    required String subjectId,
    required String activeTopicKey,
    int? termMarker,
    int maxTokens = kMaxNewTokens,
  }) async* {
    final context = await _rag.retrieveContextForQuery(
      studentQuestion,
      subjectId,
      activeTopicKey,
      termMarker: termMarker,
    );
    yield* _chat.streamGroundedAnswer(
      studentQuestion: studentQuestion,
      retrievedDbChunks: context,
      maxTokens: maxTokens,
    );
  }

  /// Non-streaming counterpart of [streamAnswer].
  Future<String> answer({
    required String studentQuestion,
    required String subjectId,
    required String activeTopicKey,
    int? termMarker,
    int maxTokens = kMaxNewTokens,
  }) async {
    final context = await _rag.retrieveContextForQuery(
      studentQuestion,
      subjectId,
      activeTopicKey,
      termMarker: termMarker,
    );
    return _chat.generateGroundedAnswer(
      studentQuestion: studentQuestion,
      retrievedDbChunks: context,
      maxTokens: maxTokens,
    );
  }

  /// The context that *would* be used for this question, without generating.
  /// Useful for a "using your teacher's notes" indicator in the UI.
  Future<String> previewContext({
    required String studentQuestion,
    required String subjectId,
    required String activeTopicKey,
    int? termMarker,
  }) {
    return _rag.retrieveContextForQuery(
      studentQuestion,
      subjectId,
      activeTopicKey,
      termMarker: termMarker,
    );
  }
}

/// Wire-up provider. Depends on whichever provider already builds the chat
/// service; pass one in explicitly at the call site if the app exposes several.
final groundedTutorServiceProvider =
    Provider.family<GroundedTutorService, QwenChatService>((ref, chat) {
  return GroundedTutorService(ref.watch(offlineRagServiceProvider), chat);
});
