import '../ai_core/inference/inference_engine.dart';
import '../ai_core/inference/runtime_config.dart';
import '../ai_core/tutor/tutor_contract.dart';

/// English-only reasoning brain (Qwen-0.6B-Instruct GGUF).
///
/// Conversational history stored here is English. Local-language strings
/// never enter this service — AfriSLM handles those hops outside.
class QwenReasoningService {
  QwenReasoningService(this._engine);

  final InferenceEngine _engine;

  /// Rolling English turns for the next prompt. Not multilingual.
  final List<({String role, String text})> _englishHistory = [];

  InferenceEngine get engine => _engine;

  bool get isReady => _engine.isReady;

  /// Append a finished English exchange. Caps length so the KV prompt stays small.
  void rememberEnglish({required String user, required String assistant}) {
    _englishHistory.add((role: 'user', text: user));
    _englishHistory.add((role: 'assistant', text: assistant));
    const cap = 8;
    if (_englishHistory.length > cap) {
      _englishHistory.removeRange(0, _englishHistory.length - cap);
    }
  }

  void clearHistory() => _englishHistory.clear();

  String historyBlock() {
    if (_englishHistory.isEmpty) return '';
    final buf = StringBuffer('THREAD:\n');
    for (final turn in _englishHistory) {
      buf.writeln('${turn.role == 'user' ? 'Student' : 'Tutor'}: ${turn.text}');
    }
    return buf.toString();
  }

  Stream<String> streamAnswer({
    required String englishUser,
    String? systemPrompt,
    int maxTokens = kMaxNewTokens,
    double temperature = kTutorTemperature,
  }) {
    return _engine.streamGenerate(
      prompt: englishUser,
      systemPrompt: systemPrompt ?? kTutorContract,
      maxTokens: maxTokens,
      temperature: temperature,
    );
  }

  Future<void> resetSession() => _engine.resetSession();
}
