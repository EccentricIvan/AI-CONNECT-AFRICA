/// Interns structural system prompts so every turn reuses the same
/// [String] instance.
///
/// llama.cpp still rebuilds the prompt each request; interned strings plus
/// the Drift translation cache skip re-reading identical clauses.
class PinnedPromptCache {
  PinnedPromptCache._();

  static final Map<String, String> _intern = {};

  static String intern(String prompt) =>
      _intern.putIfAbsent(prompt, () => prompt);

  static int get size => _intern.length;
}
