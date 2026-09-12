import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../cloud/cloud_api_settings.dart';
import 'inference_engine.dart';
import 'sanitize_llm_response.dart';

/// OpenAI-compatible chat API (OpenAI, Groq, OpenRouter, Azure-style gateways).
/// Requires internet. API key stays on-device in SharedPreferences.
class OpenAiCompatibleEngine extends InferenceEngine {
  OpenAiCompatibleEngine(this.config);

  final CloudApiConfig config;
  bool _ready = false;

  @override
  bool get isReady => _ready;

  @override
  String get backendLabel => 'Cloud · ${config.model}';

  @override
  Future<void> loadModel(String modelPath) async {
    if (!config.isConfigured) {
      throw ModelLoadException('Cloud AI is not configured. Add an API key in Settings.');
    }
    _ready = true;
  }

  @override
  Future<String> generate({
    required String prompt,
    int maxTokens = 512,
    double temperature = 0.7,
    TokenCallback? onToken,
    String? systemPrompt,
  }) async {
    if (!_ready) {
      throw StateError('Cloud AI not ready. Call loadModel() first.');
    }

    final base = config.baseUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base/chat/completions');
    final client = HttpClient();

    try {
      final request = await client.postUrl(uri).timeout(const Duration(seconds: 20));
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${config.apiKey}');
      request.headers.set('Accept', 'text/event-stream');
      request.write(jsonEncode({
        'model': config.model,
        'stream': true,
        'temperature': temperature,
        'max_tokens': maxTokens,
        'messages': [
          {
            'role': 'system',
            'content':
                'You are a supportive offline-capable tutor for African learners. '
                'Be clear, encouraging, and concise. Prefer step-by-step explanations.',
          },
          {'role': 'user', 'content': prompt},
        ],
      }));

      final response = await request.close().timeout(const Duration(seconds: 60));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final errBody = await response.transform(utf8.decoder).join();
        throw ModelLoadException(
          'Cloud AI error (${response.statusCode}): ${_shortErr(errBody)}',
        );
      }

      final cleaner = SanitizedTokenStream();
      await for (final chunk in response.transform(utf8.decoder)) {
        for (final line in chunk.split('\n')) {
          final trimmed = line.trim();
          if (trimmed.isEmpty || !trimmed.startsWith('data:')) continue;
          final data = trimmed.substring(5).trim();
          if (data == '[DONE]') continue;
          try {
            final json = jsonDecode(data) as Map<String, dynamic>;
            final choices = json['choices'] as List?;
            if (choices == null || choices.isEmpty) continue;
            final delta = choices.first['delta'] as Map<String, dynamic>?;
            final token = delta?['content'] as String? ?? '';
            if (token.isNotEmpty) {
              final visible = cleaner.add(token);
              if (visible.isNotEmpty) await emitToken(onToken, visible);
            }
          } catch (_) {
            // skip malformed SSE chunks
          }
        }
      }

      final tail = cleaner.flush();
      if (tail.isNotEmpty) await emitToken(onToken, tail);
      final text = cleaner.text;
      if (text.isEmpty) {
        throw ModelLoadException(
          'Cloud AI returned an empty reply. Check your model name and API key.',
        );
      }
      return text;
    } on TimeoutException {
      throw ModelLoadException(
        'Cloud AI timed out. Check your internet connection and try again.',
      );
    } on SocketException {
      throw ModelLoadException(
        'No internet connection for Cloud AI. Connect online or use a local model.',
      );
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<void> dispose() async {
    _ready = false;
  }

  String _shortErr(String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final err = json['error'];
      if (err is Map && err['message'] is String) return err['message'] as String;
      if (err is String) return err;
    } catch (_) {}
    if (body.length > 180) return '${body.substring(0, 180)}…';
    return body.isEmpty ? 'Unknown error' : body;
  }
}
