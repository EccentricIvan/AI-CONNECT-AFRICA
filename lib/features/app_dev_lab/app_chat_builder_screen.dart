import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../ai_core/providers/ai_provider.dart';
import '../../ai_core/model/model_manager.dart' show ModelStatus;
import '../../core/theme/app_colors.dart';
import '../../l10n/app_locale.dart';
import '../../services/ai_model_manager.dart';
import '../../shared/coding/code_autocorrect.dart';
import '../../shared/widgets/code_autocorrect_button.dart';
import '../../shared/widgets/html_preview.dart';
import '../../shared/widgets/studio_page.dart';
import '../create/dev_l10n.dart';
import '../settings/coder_package_prompt.dart';
import 'app_build_coder.dart';

class _AppType {
  const _AppType(this.id, this.name, this.featureOptions);
  final String id;
  final String name;
  final List<String> featureOptions;
}

class _QField {
  const _QField(this.key, this.question, this.hint);
  final String key, question, hint;
}

const _appTypes = [
  _AppType('notes', 'School Notes', [
    'Note list',
    'Add note form',
    'Search notes',
    'Favorite notes',
  ]),
  _AppType('budget', 'Budget Tracker', [
    'Expense list',
    'Add expense',
    'Category totals',
    'Savings goal',
  ]),
  _AppType('quiz', 'Quiz Game', [
    'Question screen',
    'Score tracker',
    'Multiple choice',
    'Restart quiz',
  ]),
  _AppType('habits', 'Habit Tracker', [
    'Daily checklist',
    'Streak counter',
    'Add habit',
    'Weekly progress',
  ]),
  _AppType('todo', 'To-Do List', [
    'Task list',
    'Add task',
    'Mark done',
    'Priority tags',
  ]),
  _AppType('market', 'Local Market', [
    'Product cards',
    'Seller contact',
    'Search items',
    'Favorites',
  ]),
];

const _askFields = [
  _QField('app_name', "What should we call your app?", 'e.g. StudySpark'),
  _QField(
    'purpose',
    'In one sentence, who is it for and what does it help with?',
    'e.g. Helps students save notes before exams',
  ),
];

const _colorThemes = {
  '1': {'name': 'Ocean Blue', 'primary': '#2563eb'},
  '2': {'name': 'Forest Green', 'primary': '#059669'},
  '3': {'name': 'Royal Purple', 'primary': '#7c3aed'},
  '4': {'name': 'Sunset Orange', 'primary': '#ea580c'},
  '5': {'name': 'Rose Pink', 'primary': '#e11d48'},
};

class AppChatBuilderScreen extends ConsumerStatefulWidget {
  const AppChatBuilderScreen({super.key});

  @override
  ConsumerState<AppChatBuilderScreen> createState() =>
      _AppChatBuilderScreenState();
}

class _AppChatBuilderScreenState extends ConsumerState<AppChatBuilderScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _codeController = TextEditingController();
  final List<_ChatMsg> _messages = [];
  final Map<String, String> _answers = {};
  final List<String> _selectedFeatures = [];

  _AppType? _appType;
  int _fieldIndex = -1;
  bool _choosingType = true;
  bool _choosingColor = false;
  bool _choosingFeatures = false;
  String _colorKey = '1';
  bool _building = false;
  bool _showStudio = false;
  String _buildNote = '';
  bool _autocorrectBusy = false;

  @override
  void initState() {
    super.initState();
    scheduleLiteRtMode(ActiveModelMode.appCoder);
    WidgetsBinding.instance.addPostFrameCallback((_) => _startIntro());
  }

  Future<void> _startIntro() async {
    await _sayBot(
      "Hi! Let's build a simple mobile app you can preview in the browser. 📱\n\n"
      "What kind of app do you want?",
    );
    await _sayBot(
      "1️⃣ School Notes\n2️⃣ Budget Tracker\n3️⃣ Quiz Game\n"
      "4️⃣ Habit Tracker\n5️⃣ To-Do List\n6️⃣ Local Market\n\n"
      "Type the number or name!",
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _sayBot(String english) async {
    final shown = await localizeDevBot(ref, english);
    if (!mounted) return;
    setState(() => _messages.add(_ChatMsg(shown, true)));
    _scrollDown();
  }

  void _addUser(String text) {
    setState(() => _messages.add(_ChatMsg(text, false)));
    _scrollDown();
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 100,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _onSend() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _building) return;
    _controller.clear();
    _addUser(text);

    final english = await localizeDevStudent(ref, text);
    if (!mounted) return;

    if (_choosingType) {
      await _handleTypeChoice(english);
    } else if (_choosingColor) {
      await _handleColorChoice(english);
    } else if (_fieldIndex >= 0 && _fieldIndex < _askFields.length) {
      await _handleFieldAnswer(text);
    } else if (_choosingFeatures) {
      await _handleFeatureChoice(english);
    }
  }

  Future<void> _handleTypeChoice(String text) async {
    final lower = text.toLowerCase();
    final matchers = <int, List<String>>{
      0: ['1', 'note', 'school'],
      1: ['2', 'budget', 'money', 'expense'],
      2: ['3', 'quiz', 'game'],
      3: ['4', 'habit'],
      4: ['5', 'todo', 'to-do', 'task'],
      5: ['6', 'market', 'shop', 'sell'],
    };
    _AppType? chosen;
    for (final e in matchers.entries) {
      for (final k in e.value) {
        if (lower.contains(k)) {
          chosen = _appTypes[e.key];
          break;
        }
      }
      if (chosen != null) break;
    }
    if (chosen == null) {
      await _sayBot("I didn't catch that. Type 1–6 or the app name.");
      return;
    }
    _appType = chosen;
    _choosingType = false;
    _choosingColor = true;
    await _sayBot("Great — ${chosen.name}! 🎨 Pick a color theme:");
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await _sayBot(
      "1️⃣ Ocean Blue\n2️⃣ Forest Green\n3️⃣ Royal Purple\n"
      "4️⃣ Sunset Orange\n5️⃣ Rose Pink\n\nType a number!",
    );
  }

  Future<void> _handleColorChoice(String text) async {
    final lower = text.trim().toLowerCase();
    String key = '1';
    for (final e in _colorThemes.entries) {
      if (lower == e.key ||
          lower.contains(e.value['name']!.toLowerCase().split(' ').first)) {
        key = e.key;
        break;
      }
    }
    _colorKey = key;
    _choosingColor = false;
    _fieldIndex = 0;
    await _sayBot("${_colorThemes[key]!['name']} selected. ✨ Two quick details:");
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await _askCurrentField();
  }

  Future<void> _askCurrentField() async {
    if (_fieldIndex < 0 || _fieldIndex >= _askFields.length) return;
    final field = _askFields[_fieldIndex];
    await _sayBot("${field.question}\n\n💡 ${field.hint}");
  }

  Future<void> _handleFieldAnswer(String text) async {
    final field = _askFields[_fieldIndex];
    _answers[field.key] = text.trim();
    _fieldIndex++;
    if (_fieldIndex >= _askFields.length) {
      _choosingFeatures = true;
      final opts = _appType!.featureOptions;
      final listed = opts.asMap().entries
          .map((e) => '${e.key + 1}️⃣ ${e.value}')
          .join('\n');
      await _sayBot(
        "Which features should this app include?\n\n$listed\n\n"
        "Type numbers like 1,2,4 — or type all",
      );
    } else {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await _askCurrentField();
    }
  }

  Future<void> _handleFeatureChoice(String text) async {
    final opts = _appType!.featureOptions;
    final lower = text.toLowerCase().trim();
    _selectedFeatures.clear();
    if (lower == 'all' || lower.contains('all')) {
      _selectedFeatures.addAll(opts);
    } else {
      for (var i = 0; i < opts.length; i++) {
        final n = '${i + 1}';
        if (RegExp('\\b$n\\b').hasMatch(lower) ||
            lower.contains(opts[i].toLowerCase())) {
          _selectedFeatures.add(opts[i]);
        }
      }
    }
    if (_selectedFeatures.isEmpty) {
      _selectedFeatures.add(opts.first);
    }
    _choosingFeatures = false;
    final recorded = tr(
      context,
      'Features recorded: ${_selectedFeatures.join(', ')}. ✅ '
      'Coding model is building your app…',
    );
    setState(() => _messages.add(_ChatMsg(recorded, true)));
    _scrollDown();
    await _buildApp();
  }

  AppBuildIntent _currentIntent() {
    final theme = _colorThemes[_colorKey]!;
    return AppBuildIntent(
      appTypeId: _appType!.id,
      appTypeName: _appType!.name,
      themeId: _colorKey,
      themeName: theme['name']!,
      themePrimary: theme['primary']!,
      answers: Map<String, String>.from(_answers),
      features: List<String>.from(_selectedFeatures),
    );
  }

  void _applyCodeEdits() {
    setState(() {});
  }

  Future<void> _autocorrectCode() async {
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
        kind: CodeAutocorrectKind.html,
        engine: engine,
      );
      if (!mounted) return;
      _codeController.text = fixed;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            fixed == before ? 'No changes needed' : 'Autocorrect applied',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      _codeController.text =
          applyHeuristicAutocorrect(before, CodeAutocorrectKind.html);
    } finally {
      if (mounted) setState(() => _autocorrectBusy = false);
    }
  }

  Future<void> _buildApp() async {
    if (_appType == null) return;
    if (!mounted) return;

    final coderOk = await promptAndFetchCoderPackage(context, ref);
    if (!coderOk || !mounted) return;

    setState(() {
      _building = true;
      _buildNote = tr(context, 'Loading coding model…');
    });

    final intent = _currentIntent();
    final fallback = fallbackAppHtml(intent);
    var html = fallback;
    var usedCoder = false;

    try {
      final info = await ref.read(programmingModelInfoProvider.future);
      if (!mounted) return;

      if (info.status != ModelStatus.ready) {
        setState(() {
          _buildNote = tr(
            context,
            'Coding model not found — using app shell.',
          );
        });
      } else {
        setState(() {
          _buildNote = tr(context, 'Coding model writing your app…');
        });
        final coder = await ref.read(aiCoderServiceProvider.future);
        if (!mounted) return;

        var lastUi = DateTime.fromMillisecondsSinceEpoch(0);
        final generated = await coder.generateAppHtml(
          intent: intent,
          onToken: (cumulative) {
            final now = DateTime.now();
            if (now.difference(lastUi).inMilliseconds < 400) return;
            lastUi = now;
            if (!mounted) return;
            final n = cumulative.length;
            setState(() {
              _buildNote = tr(
                context,
                'Coding model writing your app… ($n chars)',
              );
            });
          },
        ).timeout(
          const Duration(minutes: 3),
          onTimeout: () => null,
        );

        if (generated != null && generated.length > 200) {
          html = generated;
          usedCoder = true;
        }
      }
    } catch (_) {
      html = fallback;
      usedCoder = false;
    }

    if (!mounted) return;
    _codeController.text = html;

    final ready = usedCoder
        ? tr(
            context,
            'Your app preview is ready! 🎉 Built by the coding model. '
            'Toggle Preview / Code to view or edit.',
          )
        : tr(
            context,
            'Your app preview is ready! 🎉 '
            '(App shell — coding model was slow or incomplete.) '
            'Toggle Preview / Code to edit.',
          );

    setState(() {
      _messages.add(_ChatMsg(ready, true));
      _building = false;
      _showStudio = true;
      _buildNote = '';
    });
    _scrollDown();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.phone_android, size: 20, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(tr(context, 'App Builder')),
          ],
        ),
        actions: [
          const StudioDrawerButton(),
          TextButton(
            onPressed: () => context.push('/applab'),
            child: Text(tr(context, 'Lessons')),
          ),
          if (_showStudio)
            TextButton(
              onPressed: () => setState(() => _showStudio = false),
              child: Text(tr(context, 'Back to chat')),
            ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.18),
              ),
            ),
            child: Text(
              tr(
                context,
                _showStudio
                    ? 'Use Apply Changes & Preview to paint Base64 WebView, or Full Screen Preview for an unconstrained view.'
                    : 'Answer the prompts to record features. Build runs the coding '
                        'model, then opens Preview Layout | View Source Code.',
              ),
              style: const TextStyle(fontSize: 12, height: 1.35),
            ),
          ),
          if (_showStudio)
            Expanded(
              child: LiveHtmlStudio(
                controller: _codeController,
                onApply: _applyCodeEdits,
                toolbar: CodeAutocorrectButton(
                  busy: _autocorrectBusy,
                  onPressed: _autocorrectCode,
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                itemCount: _messages.length,
                itemBuilder: (_, i) {
                  final msg = _messages[i];
                  return _ChatBubble(text: msg.text, isBot: msg.isBot);
                },
              ),
            ),
          if (_building)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      _buildNote.isEmpty
                          ? tr(context, 'Building your app...')
                          : _buildNote,
                      style: TextStyle(color: Theme.of(context).hintColor),
                    ),
                  ),
                ],
              ),
            ),
          if (!_showStudio && !_building)
            Container(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Theme.of(context).dividerColor),
                ),
                color: Theme.of(context).colorScheme.surface,
              ),
              padding: const EdgeInsets.fromLTRB(16, 10, 12, 16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      onSubmitted: (_) => _onSend(),
                      decoration: InputDecoration(
                        hintText: _choosingType
                            ? tr(context, 'Type 1–6 or an app name…')
                            : tr(context, 'Type your answer...'),
                        border: InputBorder.none,
                      ),
                      textInputAction: TextInputAction.send,
                    ),
                  ),
                  IconButton.filled(
                    onPressed: _onSend,
                    icon: const Icon(Icons.arrow_upward),
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ChatMsg {
  const _ChatMsg(this.text, this.isBot);
  final String text;
  final bool isBot;
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.text, required this.isBot});
  final String text;
  final bool isBot;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isBot ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        constraints:
            BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isBot
              ? Theme.of(context).colorScheme.surface
              : AppColors.primary,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(isBot ? 4 : 16),
            topRight: Radius.circular(isBot ? 16 : 4),
            bottomLeft: const Radius.circular(16),
            bottomRight: const Radius.circular(16),
          ),
          border:
              isBot ? Border.all(color: Theme.of(context).dividerColor) : null,
        ),
        child: Text(
          text,
          style: TextStyle(
            color: isBot
                ? Theme.of(context).colorScheme.onSurface
                : Colors.white,
            height: 1.5,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}
