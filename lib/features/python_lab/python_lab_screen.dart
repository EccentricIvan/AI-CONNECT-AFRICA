import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../ai_core/providers/ai_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../l10n/app_locale.dart';
import '../../services/ai_model_manager.dart';
import '../../shared/coding/code_autocorrect.dart';
import '../../shared/coding/code_lab_session.dart';
import '../../shared/coding/python_tutor.dart';
import '../../shared/widgets/code_autocorrect_button.dart';
import '../../shared/widgets/code_instruction_bar.dart';
import '../settings/coder_package_prompt.dart';

class _PyLesson {
  const _PyLesson({required this.title, required this.instruction, required this.starterCode, required this.expectedOutput, this.hint, this.challenge});
  final String title, instruction, starterCode, expectedOutput;
  final String? hint, challenge;
}

const _lessons = [
  _PyLesson(
    title: 'Lesson 1: Hello Python!',
    instruction: 'print() displays text on screen. Try changing the message inside the quotes and tap RUN.',
    starterCode: '''# Your first Python program!
print("Hello World!")
print("My name is Otic")

# Try adding another print() below:
''',
    expectedOutput: 'Hello World!\nMy name is Otic',
    hint: 'Add: print("I am learning Python!")',
    challenge: 'Print your name and your age on separate lines.',
  ),
  _PyLesson(
    title: 'Lesson 2: Variables',
    instruction: 'Variables store data. Use = to assign a value. Try changing the values and see what prints.',
    starterCode: '''# Variables store information
name = "Alice"
age = 15
subject = "Mathematics"

print("Name:", name)
print("Age:", age)
print("Favourite subject:", subject)
''',
    expectedOutput: 'Name: Alice\nAge: 15\nFavourite subject: Mathematics',
    hint: 'Try adding: hobby = "coding" and printing it.',
    challenge: 'Create variables for your school name and grade, then print a sentence using them.',
  ),
  _PyLesson(
    title: 'Lesson 3: Math Operations',
    instruction: 'Python does math with +, -, *, /, ** (power), // (integer division), % (remainder).',
    starterCode: '''# Basic math
a = 10
b = 3

print("Add:", a + b)
print("Subtract:", a - b)
print("Multiply:", a * b)
print("Divide:", a / b)
print("Power:", a ** 2)
print("Remainder:", a % b)

# Area of a rectangle
length = 8
width = 5
area = length * width
print("Area:", area)
''',
    expectedOutput: 'Add: 13\nSubtract: 7\nMultiply: 30\nDivide: 3.3333\nPower: 100\nRemainder: 1\nArea: 40',
    hint: 'Try: perimeter = 2 * (length + width)',
    challenge: 'Calculate the area of a circle with radius 7.',
  ),
  _PyLesson(
    title: 'Lesson 4: If/Else Decisions',
    instruction: 'Programs make decisions with if/elif/else. The indented code runs only when the condition is True.',
    starterCode: '''# Making decisions
age = 16

if age >= 18:
    print("You are an adult")
elif age >= 13:
    print("You are a teenager")
else:
    print("You are a child")

# Grade checker
score = 75

if score >= 80:
    print("Grade: A")
elif score >= 60:
    print("Grade: B")
elif score >= 40:
    print("Grade: C")
else:
    print("Grade: F")
''',
    expectedOutput: 'You are a teenager\nGrade: B',
    hint: 'Try changing score to different values.',
    challenge: 'Add: if score == 100, print "Perfect score!"',
  ),
  _PyLesson(
    title: 'Lesson 5: Loops',
    instruction: 'for loops repeat a set number of times. while loops repeat until a condition is False.',
    starterCode: '''# For loop - count to 5
print("Counting:")
for i in range(1, 6):
    print(i)

# Loop through a list
fruits = ["apple", "banana", "mango"]
for fruit in fruits:
    print("I like", fruit)

# While loop
count = 1
while count <= 3:
    print("Count:", count)
    count = count + 1
print("Done!")
''',
    expectedOutput: 'Counting:\n1\n2\n3\n4\n5\nI like apple\nI like banana\nI like mango\nCount: 1\nCount: 2\nCount: 3\nDone!',
    hint: 'Try range(1, 11) to count to 10.',
    challenge: 'Print the 7 times table (7x1=7, 7x2=14...).',
  ),
  _PyLesson(
    title: 'Lesson 6: Functions',
    instruction: 'Functions are reusable code blocks. Define with def, call by name. They can take parameters and return values.',
    starterCode: '''# Define a function
def greet(name):
    print("Hello, " + name + "!")

greet("Alice")
greet("Bob")

# Function with return
def add(a, b):
    return a + b

result = add(5, 3)
print("5 + 3 =", result)

# Even or odd
def is_even(n):
    if n % 2 == 0:
        return "even"
    else:
        return "odd"

print("7 is", is_even(7))
print("10 is", is_even(10))
''',
    expectedOutput: 'Hello, Alice!\nHello, Bob!\n5 + 3 = 8\n7 is odd\n10 is even',
    hint: 'Try creating a multiply(a, b) function.',
    challenge: 'Write factorial(n) that calculates n!',
  ),
  _PyLesson(
    title: 'Lesson 7: Lists',
    instruction: 'Lists store multiple items. Access by index (from 0). Add with append(), sort with sort().',
    starterCode: '''# Create a list
scores = [85, 92, 78, 95, 88]
print("Scores:", scores)
print("First:", scores[0])
print("Last:", scores[-1])
print("Count:", len(scores))

scores.append(91)
print("Added 91:", scores)

print("Highest:", max(scores))
print("Lowest:", min(scores))

scores.sort()
print("Sorted:", scores)
''',
    expectedOutput: 'Scores: [85, 92, 78, 95, 88]\nFirst: 85\nLast: 88\nCount: 5\nAdded 91: [85, 92, 78, 95, 88, 91]\nHighest: 95\nLowest: 78\nSorted: [78, 85, 88, 91, 92, 95]',
    hint: 'Try scores.reverse() after sorting.',
    challenge: 'Sort 5 student names alphabetically.',
  ),
  _PyLesson(
    title: 'Lesson 8: Build a Quiz Game',
    instruction: 'Combine everything! This quiz uses variables, lists, loops, functions, and if/else.',
    starterCode: '''# Quiz Game!
print("=== Python Quiz ===")

score = 0

# Question 1
print("Q1: What does print() do?")
print("  A) Sends to printer")
print("  B) Shows text on screen")
print("  Answer: B - Correct!")
score = score + 1

# Question 2
print("Q2: Valid variable name?")
print("  A) 1name")
print("  B) student_age")
print("  Answer: B - Correct!")
score = score + 1

print("Score:", score, "/ 2")

if score == 2:
    print("Perfect!")
else:
    print("Keep trying!")
''',
    expectedOutput: '=== Python Quiz ===\nQ1: What does print() do?\n  A) Sends to printer\n  B) Shows text on screen\n  Answer: B - Correct!\nQ2: Valid variable name?\n  A) 1name\n  B) student_age\n  Answer: B - Correct!\nScore: 2 / 2\nPerfect!',
    hint: 'Add your own question.',
    challenge: 'Track wrong answers and show them at the end.',
  ),
];

// ── Screen ───────────────────────────────────────────────────────────────────

class PythonLabScreen extends ConsumerStatefulWidget {
  const PythonLabScreen({super.key});

  @override
  ConsumerState<PythonLabScreen> createState() => _PythonLabScreenState();
}

class _PythonLabScreenState extends ConsumerState<PythonLabScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _codeController = TextEditingController();
  int _currentLesson = 0;
  bool _showHint = false;
  String _output = '';
  bool _hasRun = false;
  bool _autocorrectBusy = false;
  bool _askBusy = false;

  /// The tutor's last answer, shown under the output. Never written into the
  /// editor - see [explainPythonCode].
  String _tutorAnswer = '';

  @override
  void initState() {
    super.initState();
    scheduleLiteRtMode(ActiveModelMode.appCoder);
    _tabController = TabController(length: 2, vsync: this);

    final saved =
        ref.read(codeLabSessionProvider.notifier).read(CodeLabSections.python);
    if (saved != null && !saved.isEmpty) {
      _currentLesson = saved.lessonIndex.clamp(0, _lessons.length - 1);
      _codeController.text = saved.code;
      _output = saved.result;
      _hasRun = saved.hasRun;
      _tabController.index = saved.tab.clamp(0, 1);
    } else {
      _codeController.text = _lessons[0].starterCode;
    }

    _codeController.addListener(_persistCode);
    _tabController.addListener(_persistTab);
  }

  @override
  void dispose() {
    _codeController.removeListener(_persistCode);
    _tabController.removeListener(_persistTab);
    _tabController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _persistCode() => ref
      .read(codeLabSessionProvider.notifier)
      .update(CodeLabSections.python, code: _codeController.text);

  void _persistTab() {
    if (_tabController.indexIsChanging) return;
    ref
        .read(codeLabSessionProvider.notifier)
        .update(CodeLabSections.python, tab: _tabController.index);
  }

  /// Asks the coding model about the student's Python. The reply is shown
  /// beside the code; it is never applied to it.
  Future<void> _askTutor(String question) async {
    if (_askBusy) return;
    final coderOk = await promptAndFetchCoderPackage(context, ref);
    if (!coderOk || !mounted) return;
    setState(() => _askBusy = true);
    try {
      final engine = await ref.read(programmingEngineProvider.future);
      final answer = await explainPythonCode(
        source: _codeController.text,
        question: question,
        engine: engine,
      );
      if (!mounted) return;
      if (answer == null) {
        showInstructionNoticeSnack(
          context,
          tr(context, "Couldn't answer that - try asking it a different way."),
        );
        return;
      }
      setState(() {
        _tutorAnswer = answer;
        _hasRun = true;
      });
      _tabController.animateTo(1);
    } catch (_) {
      if (!mounted) return;
      showInstructionNoticeSnack(
        context,
        tr(context, 'Something went wrong. Please try again.'),
      );
    } finally {
      if (mounted) setState(() => _askBusy = false);
    }
  }

  void _runCode() {
    // Parse print statements from the code for output
    final code = _codeController.text;
    final lesson = _lessons[_currentLesson];

    // If code is unchanged from starter, show expected output
    if (code.trim() == lesson.starterCode.trim()) {
      setState(() {
        _output = lesson.expectedOutput;
        _hasRun = true;
      });
    } else {
      // For modified code, extract print statements as best effort
      setState(() {
        _output = _simpleRun(code);
        _hasRun = true;
      });
    }
    ref.read(codeLabSessionProvider.notifier).update(
          CodeLabSections.python,
          code: _codeController.text,
          result: _output,
          lessonIndex: _currentLesson,
          hasRun: true,
        );
    _tabController.animateTo(1);
  }

  String _simpleRun(String code) {
    final lines = code.split('\n');
    final output = StringBuffer();
    final vars = <String, String>{};

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('#') || trimmed.isEmpty) continue;

      // Simple variable assignment: name = "value" or name = 123
      final assignMatch = RegExp(r'^(\w+)\s*=\s*(.+)$').firstMatch(trimmed);
      if (assignMatch != null && !trimmed.startsWith('print') && !trimmed.startsWith('if') && !trimmed.startsWith('def') && !trimmed.startsWith('for') && !trimmed.startsWith('while')) {
        final varName = assignMatch.group(1)!;
        var value = assignMatch.group(2)!.trim();
        value = value.replaceAll('"', '').replaceAll("'", '');
        vars[varName] = value;
      }

      // print() statements
      final printMatch = RegExp(r'^print\((.+)\)$').firstMatch(trimmed);
      if (printMatch != null) {
        var content = printMatch.group(1)!;
        // Replace variable references
        for (final v in vars.entries) {
          content = content.replaceAll(RegExp('\\b${v.key}\\b'), v.value);
        }
        // Clean up quotes and commas
        final parts = <String>[];
        for (final part in _splitPrintArgs(content)) {
          var p = part.trim();
          if ((p.startsWith('"') && p.endsWith('"')) || (p.startsWith("'") && p.endsWith("'"))) {
            p = p.substring(1, p.length - 1);
          }
          parts.add(p);
        }
        output.writeln(parts.join(' '));
      }
    }

    if (output.isEmpty) {
      return '(No print output detected)\n\nTip: Use print() to display results.\nExample: print("Hello!")';
    }
    return output.toString().trimRight();
  }

  List<String> _splitPrintArgs(String s) {
    final result = <String>[];
    var current = StringBuffer();
    var inString = false;
    String? quote;
    var depth = 0;

    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (inString) {
        current.write(c);
        if (c == quote) inString = false;
      } else if (c == '"' || c == "'") {
        inString = true;
        quote = c;
        current.write(c);
      } else if (c == '(') {
        depth++;
        current.write(c);
      } else if (c == ')') {
        depth--;
        current.write(c);
      } else if (c == ',' && depth == 0) {
        result.add(current.toString());
        current = StringBuffer();
      } else {
        current.write(c);
      }
    }
    if (current.isNotEmpty) result.add(current.toString());
    return result;
  }

  void _loadLesson(int index) {
    setState(() {
      _currentLesson = index;
      _showHint = false;
      _hasRun = false;
      _output = '';
      _tutorAnswer = '';
      _codeController.text = _lessons[index].starterCode;
    });
    ref.read(codeLabSessionProvider.notifier).update(
          CodeLabSections.python,
          lessonIndex: index,
          code: _codeController.text,
          result: '',
          hasRun: false,
        );
    _tabController.animateTo(0);
  }

  Future<void> _autocorrect() async {
    if (_autocorrectBusy) return;
    final before = _codeController.text;
    if (before.trim().isEmpty) return;
    final coderOk = await promptAndFetchCoderPackage(context, ref);
    if (!coderOk || !mounted) return;
    setState(() => _autocorrectBusy = true);
    try {
      final engine = await ref.read(programmingEngineProvider.future);
      final fixed = await autocorrectCode(
        source: before,
        kind: CodeAutocorrectKind.python,
        engine: engine,
      );
      if (!mounted) return;
      if (fixed != before) {
        _codeController.value = TextEditingValue(
          text: fixed,
          selection: TextSelection.collapsed(offset: fixed.length),
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(context, 'Autocorrect applied'))),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(context, 'No changes needed'))),
        );
      }
    } catch (_) {
      if (!mounted) return;
      final fixed = applyHeuristicAutocorrect(
        before,
        CodeAutocorrectKind.python,
      );
      _codeController.text = fixed;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'Applied quick local fixes'))),
      );
    } finally {
      if (mounted) setState(() => _autocorrectBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lesson = _lessons[_currentLesson];

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Row(children: [
          const Icon(Icons.terminal, size: 20, color: AppColors.primary),
          const SizedBox(width: 8),
          Text(tr(context, 'Python Lab')),
        ]),
        actions: [
          CodeAutocorrectButton(
            busy: _autocorrectBusy,
            onPressed: _autocorrect,
          ),
          IconButton(
            icon: const Icon(Icons.list),
            tooltip: tr(context, 'All lessons'),
            onPressed: () => _showLessonPicker(context),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(icon: const Icon(Icons.code), text: tr(context, 'Code')),
            Tab(icon: const Icon(Icons.terminal), text: tr(context, 'Output')),
          ],
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _runCode,
        tooltip: tr(context, 'Run in simulator'),
        icon: const Icon(Icons.play_arrow),
        label: Text(tr(context, 'SIMULATE')),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E7),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE8D4A8)),
            ),
            child: Text(
              tr(
                context,
                'Guided simulator — SIMULATE checks common print() patterns. '
                'It is not a full Python interpreter.',
              ),
              style: const TextStyle(fontSize: 12, height: 1.35),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                Column(children: [
                  _InstructionBar(
                    lesson: lesson,
                    index: _currentLesson,
                    total: _lessons.length,
                    showHint: _showHint,
                    onToggleHint: () => setState(() => _showHint = !_showHint),
                    onNext: _currentLesson < _lessons.length - 1
                        ? () => _loadLesson(_currentLesson + 1)
                        : null,
                    onPrev: _currentLesson > 0
                        ? () => _loadLesson(_currentLesson - 1)
                        : null,
                  ),
                  Expanded(child: _CodeEditor(controller: _codeController)),
                  // Same bar as the other labs, but this one asks rather than
                  // edits: the answer appears beside the output and the
                  // student's code is never touched.
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                      child: CodeInstructionBar(
                        busy: _askBusy,
                        onSubmit: _askTutor,
                        hintText: 'Ask AI about your code',
                        icon: Icons.school_outlined,
                        tooltip: 'Ask',
                      ),
                    ),
                  ),
                ]),
                _OutputView(
                  output: _output,
                  hasRun: _hasRun,
                  tutorAnswer: _tutorAnswer,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showLessonPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => ListView.builder(
        itemCount: _lessons.length,
        itemBuilder: (_, i) {
          final l = _lessons[i];
          final isCurrent = i == _currentLesson;
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: isCurrent ? const Color(0xFF3572A5) : Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Text('${i + 1}', style: TextStyle(color: isCurrent ? Colors.white : Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold)),
            ),
            title: Text(l.title, style: TextStyle(fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal)),
            subtitle: Text(l.instruction, maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () { Navigator.pop(ctx); _loadLesson(i); },
          );
        },
      ),
    );
  }
}

// ── Output view ──────────────────────────────────────────────────────────────

class _OutputView extends StatelessWidget {
  const _OutputView({
    required this.output,
    required this.hasRun,
    this.tutorAnswer = '',
  });
  final String output;
  final bool hasRun;

  /// The tutor's explanation, shown under the output in its own block so a
  /// student never mistakes the model's prose for what Python printed.
  final String tutorAnswer;

  @override
  Widget build(BuildContext context) {
    if (!hasRun) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.terminal, size: 48, color: Theme.of(context).hintColor),
            const SizedBox(height: 12),
            Text('Tap RUN to see output', style: TextStyle(color: Theme.of(context).hintColor)),
          ],
        ),
      );
    }

    return Container(
      color: const Color(0xFF1E1E2E),
      width: double.infinity,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '>>> Python Output',
              style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: Color(0xFF89B4FA)),
            ),
            const SizedBox(height: 12),
            Text(
              output,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 14,
                color: Color(0xFFA6E3A1),
                height: 1.6,
              ),
            ),
            if (tutorAnswer.isNotEmpty) ...[
              const SizedBox(height: 20),
              const Row(
                children: [
                  Icon(Icons.auto_awesome, size: 14, color: Color(0xFFF9E2AF)),
                  SizedBox(width: 6),
                  Text(
                    'Your tutor says',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: Color(0xFFF9E2AF),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF282A3A),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF45475A)),
                ),
                child: SelectableText(
                  tutorAnswer,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFFCDD6F4),
                    height: 1.55,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Instruction bar ──────────────────────────────────────────────────────────

class _InstructionBar extends StatelessWidget {
  const _InstructionBar({required this.lesson, required this.index, required this.total, required this.showHint, required this.onToggleHint, this.onNext, this.onPrev});
  final _PyLesson lesson;
  final int index, total;
  final bool showHint;
  final VoidCallback onToggleHint;
  final VoidCallback? onNext, onPrev;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(children: [
            Expanded(child: Text(lesson.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Color(0xFF3572A5)))),
            Text('${index + 1}/$total', style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Text(lesson.instruction, style: TextStyle(fontSize: 13, height: 1.5, color: Theme.of(context).colorScheme.onSurface)),
        ),
        if (showHint && lesson.hint != null)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF3572A5).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF3572A5).withValues(alpha: 0.2)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [Icon(Icons.lightbulb, size: 14, color: Color(0xFF3572A5)), SizedBox(width: 6), Text('Hint', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: Color(0xFF3572A5)))]),
              const SizedBox(height: 4),
              Text(lesson.hint!, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface)),
              if (lesson.challenge != null) ...[
                const SizedBox(height: 8),
                const Row(children: [Icon(Icons.emoji_events, size: 14, color: AppColors.createColor), SizedBox(width: 6), Text('Challenge', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AppColors.createColor))]),
                const SizedBox(height: 4),
                Text(lesson.challenge!, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface)),
              ],
            ]),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Row(children: [
            if (onPrev != null) _Btn(icon: Icons.arrow_back, label: 'Prev', onTap: onPrev!),
            if (onPrev != null) const SizedBox(width: 8),
            _Btn(icon: showHint ? Icons.lightbulb : Icons.lightbulb_outline, label: showHint ? 'Hide' : 'Hint', onTap: onToggleHint),
            const Spacer(),
            if (onNext != null) _Btn(icon: Icons.arrow_forward, label: 'Next', onTap: onNext!, primary: true),
          ]),
        ),
        const Divider(height: 1),
      ]),
    );
  }
}

class _Btn extends StatelessWidget {
  const _Btn({required this.icon, required this.label, required this.onTap, this.primary = false});
  final IconData icon; final String label; final VoidCallback onTap; final bool primary;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: primary ? const Color(0xFF3572A5) : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(6),
          border: primary ? null : Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: primary ? Colors.white : Theme.of(context).colorScheme.onSurface),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: primary ? Colors.white : Theme.of(context).colorScheme.onSurface)),
        ]),
      ),
    );
  }
}

class _CodeEditor extends StatelessWidget {
  const _CodeEditor({required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1E1E2E),
      child: TextField(
        controller: controller,
        maxLines: null,
        expands: true,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 13, color: Color(0xFFCDD6F4), height: 1.5),
        decoration: const InputDecoration(
          border: InputBorder.none,
          contentPadding: EdgeInsets.all(16),
          hintText: 'Write your Python code here...',
          hintStyle: TextStyle(fontFamily: 'monospace', fontSize: 13, color: Color(0xFF585B70)),
        ),
        textAlignVertical: TextAlignVertical.top,
        keyboardType: TextInputType.multiline,
      ),
    );
  }
}
