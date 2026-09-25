import 'inference_engine.dart';

/// Canned demo replies when no real local model is available.
/// Used on web, when the chat model is missing, when load fails,
/// and in unit tests.
class MockEngine extends InferenceEngine {
  MockEngine({this.demoReason = DemoReason.generic});

  final DemoReason demoReason;
  bool _ready = false;

  @override
  bool get isReady => _ready;

  @override
  bool get isDemo => true;

  @override
  String get backendLabel => 'Demo mode';

  @override
  Future<void> loadModel(String modelPath) async {
    await Future.delayed(const Duration(milliseconds: 300));
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
    return _mockResponse(prompt, onToken: onToken);
  }

  Future<String> _mockResponse(String prompt, {TokenCallback? onToken}) async {
    final response = _pickResponse(prompt);
    for (final word in response.split(' ')) {
      final token = '$word ';
      await emitToken(onToken, token);
      await Future.delayed(const Duration(milliseconds: 40));
    }
    return response;
  }

  String _pickResponse(String prompt) {
    final lower = prompt.toLowerCase();
    if (lower.contains('photosynthesis')) {
      return 'Photosynthesis is how plants convert sunlight into food. '
          'Chlorophyll in the leaves absorbs light, which drives a reaction '
          'that turns carbon dioxide and water into glucose and oxygen. '
          'Now — can you tell me: what part of the plant cell does this happen in?';
    }
    if (lower.contains('python') || lower.contains('code')) {
      return 'Great choice! Python is one of the most beginner-friendly languages. '
          'Let\'s start with the basics: a variable stores a value. '
          'Try this: `name = "Tutor"` then `print(name)`. '
          'What do you think will happen when you run it?';
    }
    if (lower.contains('entrepreneur')) {
      return 'Entrepreneurship is about spotting a problem and building a solution. '
          'Every successful business started with someone noticing an unmet need. '
          'Think about your own community — what problem do you see every day '
          'that nobody has solved yet?';
    }
    return 'That\'s a great question! Let me break it down step by step. '
        'This topic has several interesting angles we can explore together. '
        'To get the most out of your learning, install the learning packages '
        'in Settings. What part of this topic interests you most?';
  }

  @override
  Future<void> dispose() async {
    _ready = false;
  }
}

/// Why the app fell back to demo answers.
enum DemoReason {
  web,
  modelNotInstalled,
  ollamaUnavailable,
  loadFailed,
  generic,
}

extension DemoReasonMessage on DemoReason {
  String get title => switch (this) {
        DemoReason.web => 'Demo answers (web)',
        DemoReason.modelNotInstalled => 'Demo answers — packages not installed',
        DemoReason.ollamaUnavailable => 'Demo answers — translation not ready',
        DemoReason.loadFailed => 'Demo answers — assistant could not start',
        DemoReason.generic => 'Demo answers',
      };

  String get detail => switch (this) {
        DemoReason.web =>
          'The browser version cannot run the classroom assistant. Replies are sample text only.',
        DemoReason.modelNotInstalled =>
          'Install the learning packages in Settings to get real tutor answers.',
        DemoReason.ollamaUnavailable =>
          'Install the language pack in Settings for answers in your language.',
        DemoReason.loadFailed =>
          'The classroom assistant could not start. Check Settings, then try again.',
        DemoReason.generic =>
          'Showing sample replies until setup is finished.',
      };
}
