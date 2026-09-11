/// Compressed English chat memory for the tutor prompt.
///
/// Stores short turns and verified facts only — never local-language
/// strings and never a full transcript.
class ConversationMemory {
  final List<({String role, String text})> turns = [];
  final List<String> established = [];

  bool get isEmpty => turns.isEmpty;

  void clear() {
    turns.clear();
    established.clear();
  }

  void remember({
    required String student,
    required String tutor,
    List<String> verified = const [],
  }) {
    turns.add((role: 'student', text: student.trim()));
    turns.add((role: 'tutor', text: tutor.trim()));
    established.addAll(verified.where((e) => e.trim().isNotEmpty));
    const cap = 8;
    if (turns.length > cap) {
      turns.removeRange(0, turns.length - cap);
    }
    const factCap = 8;
    if (established.length > factCap) {
      established.removeRange(0, established.length - factCap);
    }
  }

  bool isContinuing(String message) {
    final t = message.trim().toLowerCase();
    if (t.isEmpty || turns.isEmpty) return false;
    const shorts = {
      'yes', 'yeah', 'yep', 'ok', 'okay', 'sure', 'no',
      'why', 'how', 'what', 'more', 'again', 'explain',
      'continue', 'go on', 'and then',
    };
    if (shorts.contains(t)) return true;
    if (t.length <= 12 && !t.contains('?')) return true;
    return false;
  }

  bool isCorrection(String message) {
    final t = message.trim().toLowerCase();
    return t.contains("that's wrong") ||
        t.contains('that is wrong') ||
        t.contains('incorrect') ||
        t.contains('not true') ||
        t.startsWith('no,') ||
        t.contains('you are wrong');
  }

  void noteCorrection() {
    if (established.isNotEmpty) established.removeLast();
  }

  String resolveCurrent(String message) {
    if (!isContinuing(message) || turns.isEmpty) return message;
    final lastStudent = turns.reversed.firstWhere(
      (t) => t.role == 'student',
      orElse: () => (role: 'student', text: message),
    );
    return '${lastStudent.text} (follow-up: $message)';
  }

  String promptBlock() {
    if (turns.isEmpty && established.isEmpty) return '';
    final buf = StringBuffer();
    if (turns.isNotEmpty) {
      buf.writeln('THREAD:');
      for (final turn in turns) {
        buf.writeln(
          '${turn.role == 'student' ? 'Student' : 'Tutor'}: ${turn.text}',
        );
      }
    }
    if (established.isNotEmpty) {
      buf.writeln('ESTABLISHED:');
      for (final fact in established) {
        buf.writeln('- $fact');
      }
    }
    return buf.toString();
  }
}
