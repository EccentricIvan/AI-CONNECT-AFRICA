import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../ai_core/providers/ai_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../l10n/app_locale.dart';
import '../../shared/coding/code_autocorrect.dart';
import '../../shared/widgets/code_autocorrect_button.dart';
import '../../shared/widgets/html_preview.dart';
import '../../shared/widgets/studio_page.dart';

// ── Lesson data ──────────────────────────────────────────────────────────────

class _LabLesson {
  const _LabLesson({
    required this.title,
    required this.instruction,
    required this.starterCode,
    this.hint,
    this.challenge,
  });
  final String title;
  final String instruction;
  final String starterCode;
  final String? hint;
  final String? challenge;
}

const _lessons = [
  _LabLesson(
    title: 'Lesson 1: Your First Web Page',
    instruction:
        'Every web page starts with HTML tags. The <h1> tag creates a big heading '
        'and <p> creates a paragraph. Try changing the text inside the tags below, '
        'then tap RUN to see your page!',
    starterCode: '''<!DOCTYPE html>
<html>
<head><title>My Page</title></head>
<body>

  <h1>Hello World!</h1>
  <p>This is my first web page.</p>

</body>
</html>''',
    hint: 'Try adding another <p> paragraph below the first one.',
    challenge: 'Add a second heading using <h2> and another paragraph.',
  ),
  _LabLesson(
    title: 'Lesson 2: Adding Style with CSS',
    instruction:
        'CSS changes how your page looks — colors, fonts, spacing. '
        'CSS goes inside <style> tags in the <head>. '
        'Try changing the color value to "red" or "green" and tap RUN.',
    starterCode: '''<!DOCTYPE html>
<html>
<head>
  <style>
    body {
      font-family: Arial, sans-serif;
      background-color: #f0f4f8;
      padding: 20px;
    }
    h1 {
      color: #4F46E5;
    }
    p {
      color: #333;
      font-size: 18px;
    }
  </style>
</head>
<body>

  <h1>Styled Page</h1>
  <p>This text is styled with CSS!</p>

</body>
</html>''',
    hint: 'Try changing background-color to lightblue or #ffd700 (gold).',
    challenge: 'Add a border to the paragraph: border: 2px solid #4F46E5;',
  ),
  _LabLesson(
    title: 'Lesson 3: Links and Images',
    instruction:
        'Links use <a href="url">text</a> to connect pages. '
        'Images use <img src="url" alt="description">. '
        'Edit the link text and try adding another link below it.',
    starterCode: '''<!DOCTYPE html>
<html>
<head>
  <style>
    body { font-family: Arial; padding: 20px; }
    a { color: #4F46E5; font-size: 18px; }
    img { max-width: 100%; border-radius: 12px; margin-top: 16px; }
  </style>
</head>
<body>

  <h1>Links and Images</h1>
  <p>Click the link below:</p>
  <a href="https://example.com">Visit Example.com</a>

  <p>Here is an image:</p>
  <img src="https://picsum.photos/400/200" alt="Random photo">

</body>
</html>''',
    hint: 'Add another link: <a href="https://google.com">Google</a>',
    challenge: 'Create a list of 3 links using <ul> and <li> tags.',
  ),
  _LabLesson(
    title: 'Lesson 4: Building a Card',
    instruction:
        'Cards are boxes with rounded corners and shadows — used everywhere in modern design. '
        'A <div> with CSS creates a card. Try changing the border-radius or box-shadow values.',
    starterCode: '''<!DOCTYPE html>
<html>
<head>
  <style>
    body {
      font-family: Arial;
      background: #f0f4f8;
      padding: 20px;
    }
    .card {
      background: white;
      border-radius: 16px;
      padding: 24px;
      box-shadow: 0 4px 12px rgba(0,0,0,0.1);
      max-width: 400px;
    }
    .card h2 { color: #4F46E5; margin-top: 0; }
    .card p { color: #555; line-height: 1.6; }
    .btn {
      background: #4F46E5;
      color: white;
      border: none;
      padding: 10px 24px;
      border-radius: 8px;
      font-size: 16px;
      cursor: pointer;
    }
  </style>
</head>
<body>

  <div class="card">
    <h2>My First Card</h2>
    <p>Cards are everywhere — apps, websites, social media. You just built one!</p>
    <button class="btn">Learn More</button>
  </div>

</body>
</html>''',
    hint: 'Try adding a second card below the first one.',
    challenge: 'Create a profile card with a name, description, and a colored border-left.',
  ),
  _LabLesson(
    title: 'Lesson 5: Interactive JavaScript',
    instruction:
        'JavaScript makes pages interactive. '
        'The code below changes the heading color when you click the button. '
        'Try changing what happens — maybe change the text instead of the color!',
    starterCode: '''<!DOCTYPE html>
<html>
<head>
  <style>
    body { font-family: Arial; padding: 20px; background: #f0f4f8; }
    h1 { color: #4F46E5; transition: color 0.3s; }
    .btn {
      background: #4F46E5; color: white; border: none;
      padding: 12px 24px; border-radius: 8px;
      font-size: 16px; cursor: pointer; margin-top: 12px;
    }
    #counter { font-size: 48px; font-weight: bold; color: #4F46E5; }
  </style>
</head>
<body>

  <h1 id="title">Click the Button!</h1>
  <p id="counter">0</p>
  <button class="btn" onclick="count()">Click Me</button>

  <script>
    let clicks = 0;
    function count() {
      clicks++;
      document.getElementById('counter').textContent = clicks;
      if (clicks >= 10) {
        document.getElementById('title').textContent = 'You did it! 🎉';
      }
    }
  </script>

</body>
</html>''',
    hint: 'Try changing the message that appears at 10 clicks.',
    challenge: 'Add a reset button that sets the counter back to 0.',
  ),
  _LabLesson(
    title: 'Lesson 6: Forms and Input',
    instruction:
        'Forms collect user input. <input> creates text fields, <textarea> for multi-line, '
        '<select> for dropdowns. This form greets the user by name. '
        'Try adding another input field for their favorite subject!',
    starterCode: '''<!DOCTYPE html>
<html>
<head>
  <style>
    body { font-family: Arial; padding: 20px; background: #f0f4f8; }
    .form-card {
      background: white; border-radius: 16px;
      padding: 24px; max-width: 400px;
      box-shadow: 0 4px 12px rgba(0,0,0,0.1);
    }
    input, select {
      width: 100%; padding: 10px; margin: 8px 0 16px;
      border: 2px solid #ddd; border-radius: 8px;
      font-size: 16px; box-sizing: border-box;
    }
    input:focus { border-color: #4F46E5; outline: none; }
    .btn {
      background: #4F46E5; color: white; border: none;
      padding: 12px 24px; border-radius: 8px;
      font-size: 16px; cursor: pointer; width: 100%;
    }
    #greeting { color: #4F46E5; font-size: 20px; margin-top: 16px; }
  </style>
</head>
<body>

  <div class="form-card">
    <h2>Welcome Form</h2>
    <label>Your Name:</label>
    <input type="text" id="nameInput" placeholder="Enter your name">

    <label>Your Age:</label>
    <select id="ageSelect">
      <option>Under 13</option>
      <option>13-17</option>
      <option>18-25</option>
      <option>Over 25</option>
    </select>

    <button class="btn" onclick="greet()">Say Hello</button>
    <p id="greeting"></p>
  </div>

  <script>
    function greet() {
      const name = document.getElementById('nameInput').value;
      const age = document.getElementById('ageSelect').value;
      if (name) {
        document.getElementById('greeting').textContent =
          'Hello, ' + name + '! Age group: ' + age;
      } else {
        document.getElementById('greeting').textContent = 'Please enter your name!';
      }
    }
  </script>

</body>
</html>''',
    hint: 'Add a <textarea> for a short bio after the age selector.',
    challenge: 'Validate the form — show an error if name is empty when submitted.',
  ),
  _LabLesson(
    title: 'Lesson 7: Flexbox Layout',
    instruction:
        'Flexbox arranges items in rows or columns easily. '
        'display: flex on a container, then use justify-content and align-items. '
        'Try changing "row" to "column" and see what happens!',
    starterCode: '''<!DOCTYPE html>
<html>
<head>
  <style>
    body { font-family: Arial; padding: 20px; background: #f0f4f8; }
    .flex-container {
      display: flex;
      flex-direction: row;
      gap: 16px;
      flex-wrap: wrap;
    }
    .box {
      background: #4F46E5;
      color: white;
      padding: 24px;
      border-radius: 12px;
      text-align: center;
      font-size: 18px;
      font-weight: bold;
      flex: 1;
      min-width: 100px;
    }
    .box:nth-child(2) { background: #0EA5E9; }
    .box:nth-child(3) { background: #10B981; }
    .box:nth-child(4) { background: #F59E0B; }
  </style>
</head>
<body>

  <h1>Flexbox Layout</h1>
  <div class="flex-container">
    <div class="box">Box 1</div>
    <div class="box">Box 2</div>
    <div class="box">Box 3</div>
    <div class="box">Box 4</div>
  </div>

</body>
</html>''',
    hint: 'Try justify-content: center; or space-between; on the container.',
    challenge: 'Create a navigation bar using flexbox with 4 links in a row.',
  ),
  _LabLesson(
    title: 'Lesson 8: Build a Mini Website',
    instruction:
        'Combine everything you learned! This is a complete mini website with '
        'a header, navigation, content cards, and footer. '
        'Customize it — change the name, colors, and content to make it yours!',
    starterCode: '''<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    * { margin: 0; box-sizing: border-box; }
    body { font-family: Arial, sans-serif; background: #f0f4f8; color: #1a202c; }

    header {
      background: #4F46E5; color: white;
      padding: 20px; text-align: center;
    }
    nav {
      background: #3730A3; padding: 10px;
      display: flex; justify-content: center; gap: 20px;
    }
    nav a { color: white; text-decoration: none; font-weight: bold; }
    nav a:hover { text-decoration: underline; }

    .content { padding: 20px; max-width: 600px; margin: auto; }

    .card {
      background: white; border-radius: 12px; padding: 20px;
      box-shadow: 0 2px 8px rgba(0,0,0,0.1); margin-bottom: 16px;
    }
    .card h3 { color: #4F46E5; }

    footer {
      background: #1E293B; color: #94A3B8;
      text-align: center; padding: 16px; margin-top: 32px;
    }

    .btn {
      background: #4F46E5; color: white; border: none;
      padding: 10px 20px; border-radius: 8px; cursor: pointer;
    }
  </style>
</head>
<body>

  <header>
    <h1>My Website</h1>
    <p>Built with HTML, CSS & JS</p>
  </header>

  <nav>
    <a href="#home">Home</a>
    <a href="#about">About</a>
    <a href="#contact">Contact</a>
  </nav>

  <div class="content">
    <div class="card">
      <h3>Welcome!</h3>
      <p>This is a complete mini website. You built this!</p>
      <button class="btn" onclick="alert('You clicked!')">Click Me</button>
    </div>

    <div class="card">
      <h3>About Me</h3>
      <p>I am learning web development with AI Connect Africa.
         I can now build web pages with HTML, style them with CSS,
         and make them interactive with JavaScript.</p>
    </div>

    <div class="card">
      <h3>My Skills</h3>
      <ul>
        <li>HTML — Structure</li>
        <li>CSS — Styling</li>
        <li>JavaScript — Interactivity</li>
      </ul>
    </div>
  </div>

  <footer>
    <p>&copy; 2024 My Website — Built with AI Connect Africa</p>
  </footer>

</body>
</html>''',
    hint: 'Change the header color and add your real name.',
    challenge: 'Add a dark mode toggle button using JavaScript that switches background and text colors!',
  ),
];

// ── Screen ───────────────────────────────────────────────────────────────────

class WebDevLabScreen extends ConsumerStatefulWidget {
  const WebDevLabScreen({super.key});

  @override
  ConsumerState<WebDevLabScreen> createState() => _WebDevLabScreenState();
}

class _WebDevLabScreenState extends ConsumerState<WebDevLabScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _codeController = TextEditingController();
  WebViewController? _webViewController;
  int _currentLesson = 0;
  bool _showHint = false;
  bool _autocorrectBusy = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _codeController.text = _lessons[0].starterCode;
    _initWebView();
  }

  void _initWebView() {
    unawaited(() async {
      final c = await createPreviewWebViewController();
      if (!mounted) return;
      setState(() => _webViewController = c);
    }());
  }

  @override
  void dispose() {
    _tabController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _runCode() {
    final html = _codeController.text;
    final c = _webViewController;
    if (c != null) {
      loadHtmlPreview(c, html);
    }
    _tabController.animateTo(1);
  }

  Future<void> _autocorrect() async {
    if (_autocorrectBusy) return;
    final before = _codeController.text;
    if (before.trim().isEmpty) return;
    setState(() => _autocorrectBusy = true);
    try {
      final engine = await ref.read(programmingEngineProvider.future);
      final fixed = await autocorrectCode(
        source: before,
        kind: CodeAutocorrectKind.html,
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
        CodeAutocorrectKind.html,
      );
      _codeController.text = fixed;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'Applied quick local fixes'))),
      );
    } finally {
      if (mounted) setState(() => _autocorrectBusy = false);
    }
  }

  void _loadLesson(int index) {
    setState(() {
      _currentLesson = index;
      _showHint = false;
      _codeController.text = _lessons[index].starterCode;
    });
    _tabController.animateTo(0);
  }

  void _nextLesson() {
    if (_currentLesson < _lessons.length - 1) {
      _loadLesson(_currentLesson + 1);
    }
  }

  void _prevLesson() {
    if (_currentLesson > 0) {
      _loadLesson(_currentLesson - 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lesson = _lessons[_currentLesson];

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.code, size: 20, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(tr(context, 'Web Dev Lab')),
          ],
        ),
        actions: [
          CodeAutocorrectButton(
            busy: _autocorrectBusy,
            onPressed: _autocorrect,
          ),
          const StudioDrawerButton(),
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
            Tab(icon: const Icon(Icons.visibility), text: tr(context, 'Preview')),
          ],
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _runCode,
        icon: const Icon(Icons.play_arrow),
        label: Text(tr(context, 'RUN')),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Code tab with instruction
          Column(
            children: [
              _InstructionBar(
                lesson: lesson,
                lessonIndex: _currentLesson,
                totalLessons: _lessons.length,
                showHint: _showHint,
                onToggleHint: () => setState(() => _showHint = !_showHint),
                onNext: _currentLesson < _lessons.length - 1 ? _nextLesson : null,
                onPrev: _currentLesson > 0 ? _prevLesson : null,
              ),
              Expanded(child: _CodeEditor(controller: _codeController)),
            ],
          ),
          // Preview tab
          _Preview(controller: _webViewController),
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
              backgroundColor: isCurrent
                  ? AppColors.primary
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Text(
                '${i + 1}',
                style: TextStyle(
                  color: isCurrent ? Colors.white : Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: Text(l.title, style: TextStyle(fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal)),
            subtitle: Text(l.instruction, maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () {
              Navigator.pop(ctx);
              _loadLesson(i);
            },
          );
        },
      ),
    );
  }
}

// ── Instruction bar ──────────────────────────────────────────────────────────

class _InstructionBar extends StatelessWidget {
  const _InstructionBar({
    required this.lesson,
    required this.lessonIndex,
    required this.totalLessons,
    required this.showHint,
    required this.onToggleHint,
    required this.onNext,
    required this.onPrev,
  });

  final _LabLesson lesson;
  final int lessonIndex;
  final int totalLessons;
  final bool showHint;
  final VoidCallback onToggleHint;
  final VoidCallback? onNext;
  final VoidCallback? onPrev;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Lesson title + navigation
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    lesson.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                Text(
                  '${lessonIndex + 1}/$totalLessons',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).hintColor,
                  ),
                ),
              ],
            ),
          ),
          // Instruction text
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              lesson.instruction,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          // Hint + challenge
          if (showHint && lesson.hint != null)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.lightbulb, size: 14, color: AppColors.primary),
                      SizedBox(width: 6),
                      Text('Hint', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AppColors.primary)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(lesson.hint!, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface)),
                  if (lesson.challenge != null) ...[
                    const SizedBox(height: 8),
                    const Row(
                      children: [
                        Icon(Icons.emoji_events, size: 14, color: AppColors.createColor),
                        SizedBox(width: 6),
                        Text('Challenge', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AppColors.createColor)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(lesson.challenge!, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface)),
                  ],
                ],
              ),
            ),
          // Action buttons
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(
              children: [
                if (onPrev != null)
                  _SmallButton(icon: Icons.arrow_back, label: 'Prev', onTap: onPrev!),
                if (onPrev != null) const SizedBox(width: 8),
                _SmallButton(
                  icon: showHint ? Icons.lightbulb : Icons.lightbulb_outline,
                  label: showHint ? 'Hide Hint' : 'Hint',
                  onTap: onToggleHint,
                ),
                const Spacer(),
                if (onNext != null)
                  _SmallButton(icon: Icons.arrow_forward, label: 'Next Lesson', onTap: onNext!, primary: true),
              ],
            ),
          ),
          const Divider(height: 1),
        ],
      ),
    );
  }
}

class _SmallButton extends StatelessWidget {
  const _SmallButton({required this.icon, required this.label, required this.onTap, this.primary = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: primary ? AppColors.primary : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(6),
          border: primary ? null : Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: primary ? Colors.white : Theme.of(context).colorScheme.onSurface),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: primary ? Colors.white : Theme.of(context).colorScheme.onSurface)),
          ],
        ),
      ),
    );
  }
}

// ── Code editor ──────────────────────────────────────────────────────────────

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
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          color: Color(0xFFCDD6F4),
          height: 1.5,
        ),
        decoration: const InputDecoration(
          border: InputBorder.none,
          contentPadding: EdgeInsets.all(16),
          hintText: 'Write your HTML, CSS, and JavaScript here...',
          hintStyle: TextStyle(fontFamily: 'monospace', fontSize: 13, color: Color(0xFF585B70)),
        ),
        textAlignVertical: TextAlignVertical.top,
        keyboardType: TextInputType.multiline,
      ),
    );
  }
}

// ── Preview ──────────────────────────────────────────────────────────────────

class _Preview extends StatelessWidget {
  const _Preview({required this.controller});
  final WebViewController? controller;

  @override
  Widget build(BuildContext context) {
    if (controller == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.web, size: 48, color: Theme.of(context).hintColor),
            const SizedBox(height: 12),
            Text('Tap RUN to see your page', style: TextStyle(color: Theme.of(context).hintColor)),
          ],
        ),
      );
    }
    return WebViewWidget(controller: controller!);
  }
}
