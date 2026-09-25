import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../ai_core/providers/ai_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../l10n/app_locale.dart';
import '../../shared/coding/code_autocorrect.dart' show CodeAutocorrectKind;
import '../../shared/coding/code_instruction_edit.dart';
import '../../shared/coding/html_images.dart' show maskEmbeddedImages;
import '../../shared/coding/interactive_html.dart' show escapeHtml;
import '../../shared/widgets/code_instruction_bar.dart';
import '../../shared/widgets/html_preview.dart';
import '../../services/projects/project_providers.dart';
import '../projects/project_actions.dart';
import '../projects/project_files_sheet.dart';
import '../projects/scaffold/project_scaffold.dart';
import '../projects/widgets/project_tools_bar.dart';
import '../create/dev_l10n.dart';
import '../settings/coder_package_prompt.dart';
import 'app_build_coder.dart';

class _AppType {
  const _AppType(
    this.id,
    this.name,
    this.featureOptions, {
    this.templateId = 'generic',
    this.autoFields = const {},
  });
  final String id;
  final String name;
  final List<String> featureOptions;

  /// Screen template under `assets/templates/apps/` this type builds from.
  final String templateId;

  /// Sample copy pools filled in at build time, so a student's screen looks
  /// like a real product instead of empty placeholders.
  final Map<String, List<String>> autoFields;
}

class _QField {
  const _QField(this.key, this.question, this.hint);
  final String key, question, hint;
}

final _rng = Random();
String _pick(List<String> options) => options[_rng.nextInt(options.length)];

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
  _AppType(
    'farm',
    'Farm / Crop Monitor',
    ['Field list', 'Weather today', 'Crop health', 'Harvest log'],
    templateId: 'farm',
    autoFields: {
      'owner_name': ['Annca', 'Harris', 'Joseph', 'Amina'],
      'location': ['Mukono, Uganda', 'Central Valley', 'Jinja, Uganda', 'Nakuru, Kenya'],
      'temperature': ['24°C', '32°C', '27°C'],
      'humidity': ['85%', '78%', '64%'],
      'rainfall': ['8 mm', '0 mm', '12 mm'],
      'wind': ['13 km/h', '7 m/s', '9 km/h'],
      'crop1': ['Maize', 'Rice', 'Carrots'],
      'crop2': ['Beans', 'Wheat', 'Vegetable'],
      'crop3': ['Coffee', 'Potato', 'Fruit'],
      'field1_name': ['My Garden Field', 'North Field', 'Riverside Plot'],
      'field1_note': ['Healthy growth, irrigation on schedule.', 'Ready for harvest in two weeks.'],
      'field2_name': ['East Field', 'Hill Plot', 'Lower Field'],
      'field2_note': ['Watch for pests this week.', 'Newly planted, germinating well.'],
      'total_area': ['12 ha', '45 acres', '8 ha'],
      'plant_age': ['45 days', '2 months', '18 days'],
      'soil_quality': ['75%', '82%', '68%'],
      'yield_amount': ['15 tons', '22 tons', '9 tons'],
    },
  ),
  _AppType(
    'shop',
    'Online Shop / Store',
    ['Product grid', 'Search items', 'Cart & checkout', 'Favorites'],
    templateId: 'shop',
    autoFields: {
      'location': ['Kampala Road, 21', 'Main Street, Nairobi', 'Plot 8, Entebbe'],
      'cat1': ['Home', 'Furniture', 'Fabrics'],
      'cat2': ['Clothes', 'Fashion', 'Shoes'],
      'cat3': ['Electronics', 'Lighting', 'Phones'],
      'cat4': ['Plants', 'Decor', 'Garden'],
      'promo_title': ['Pay in instalments', 'Free delivery this week', 'Save up to 30%'],
      'promo_note': ['No deposit needed on selected items.', 'On every order above 50,000 UGX.'],
      'product1_name': ['Swivel chair', 'Woven basket', 'Cushion cover'],
      'product1_price': ['120,000 UGX', '35,000 UGX', '18,000 UGX'],
      'product2_name': ['Table lamp', 'Glass tumbler', 'Wall clock'],
      'product2_price': ['45,000 UGX', '9,000 UGX', '60,000 UGX'],
    },
  ),
  _AppType(
    'learn',
    'Learning / Course App',
    ['Course list', 'Lesson player', 'Progress tracker', 'Quizzes'],
    templateId: 'learn',
    autoFields: {
      'learner_name': ['Sofia', 'Jerel', 'Amina', 'Daniel'],
      'banner_title': ['Find your lesson for today', 'Learn something new today', 'Pick up where you left off'],
      'banner_note': ['Over 100 offline lessons across every subject on your device.', 'Short lessons that work with no internet at all.'],
      'cat1': ['Design', 'Art', 'Writing'],
      'cat2': ['Coding', 'Web Design', 'ICT'],
      'cat3': ['Maths', 'Numbers', 'Algebra'],
      'cat4': ['Science', 'Biology', 'Physics'],
      'course1_name': ['Intro to Web Design', 'Algebra Basics', 'Biology Foundations'],
      'course1_meta': ['12 lessons · 6h 30m', '18 lessons · 4h 10m'],
      'course2_name': ['JavaScript Fundamentals', 'Chemistry Basics', 'Creative Writing'],
      'course2_meta': ['24 lessons · 8h 41m', '9 lessons · 3h 05m'],
    },
  ),
  _AppType(
    'pos',
    'Shop Till / Sales Point',
    ['Register sale', 'Product list', 'Daily totals', 'Receipts'],
    templateId: 'pos',
    autoFields: {
      'owner_name': ['June', 'Peter', 'Sarah', 'Moses'],
      'shop_name': ['The Craft Shop', 'Corner Store', 'Netro Creative'],
      'today': ['Monday, 1 February', 'Today', 'Tuesday, 14 March'],
      'receipts': ['4', '19', '27'],
      'total_sales': ['362,290', '1,240,000', '86,400'],
      'menu_label': ['Menu', 'Products', 'Stock'],
    },
  ),
  _AppType(
    'social',
    'Community / Social App',
    ['Feed', 'Groups', 'Discover', 'Profile'],
    templateId: 'social',
    autoFields: {
      'community_tag': ['Community & Culture', 'Made for creators', 'Connect and share'],
      'tab1': ['Following', 'For you', 'Trending'],
      'tab2': ['Discover', 'Nearby', 'Popular'],
      'tab3': ['Groups', 'Events', 'Saved'],
      'post1_title': ['Culture Festival Highlights', 'Market Day Recap', 'Sunset Over the Hills'],
      'post1_author': ['Amara K.', 'Kwame O.', 'Zanele M.'],
      'post1_likes': ['1.5K', '820', '2.3K'],
      'post2_title': ['DIY Traditional Fashion', 'Weekend Craft Fair', 'New Fabric Drop'],
      'post2_author': ['Tendai M.', 'Aisha B.', 'Kofi A.'],
      'post2_likes': ['183K', '4.2K', '9.6K'],
      'post3_title': ['A Map of Our Roots', 'Where We Come From', 'Community Stories'],
      'post3_author': ['Chidi N.', 'Fatima Y.', 'Noma S.'],
      'post3_likes': ['100K', '15K', '6.8K'],
      'post4_title': ['My First Vlog', 'Behind the Scenes', 'A Day in the Village'],
      'post4_author': ['Nia F.', 'Emeka T.', 'Layla R.'],
      'post4_likes': ['2.7M', '340K', '58K'],
    },
  ),
  _AppType(
    'eduplatform',
    'Course Marketplace App',
    ['Course catalog', 'Mentor profiles', 'Lesson progress', 'Enroll'],
    templateId: 'eduplatform',
    autoFields: {
      'course1_name': ['Figma Master Class for Beginners', 'Intro to Bootstrap', 'UI/UX Fundamentals'],
      'course1_tutor': ['Trolentik Korlen', 'Jane Achan', 'Marlin Reyes'],
      'course1_due': ['28 lessons', 'Due Nov 2', '6h 30m'],
      'course1_level': ['Beginner', 'Intermediate'],
      'course2_name': ['Web Design Fundamentals', 'JavaScript Basics', 'Graphic Design Pro'],
      'course2_tutor': ['Simons Lee', 'Peter Okot', 'Jesica Nabb'],
      'course2_due': ['24 lessons', 'Due Nov 9', '8h 20m'],
      'course2_level': ['Intermediate', 'Beginner'],
      'course3_name': ['App Development', 'Prototype with Figma', 'Mobile UI Essentials'],
      'course3_tutor': ['Marlin Torres', 'Grace Auma', 'David Oduya'],
      'course3_due': ['15 lessons', 'Due Nov 16', '46 min'],
      'course3_level': ['Advanced', 'Beginner'],
      'mentor1_name': ['Marlin', 'Grace', 'David'],
      'mentor1_subject': ['UI/UX Design', 'Mathematics', 'Web Design'],
      'mentor2_name': ['Simons', 'Peter', 'Jesica'],
      'mentor2_subject': ['Web Design', 'Physics', 'Graphic Design'],
      'mentor3_name': ['Jesica', 'David', 'Simons'],
      'mentor3_subject': ['UI/UX Design', 'App Dev', 'Illustration'],
    },
  ),
  _AppType(
    'orders',
    'Order Pipeline App',
    ['Order stages', 'Revenue chart', 'Client details', 'Notifications'],
    templateId: 'orders',
    autoFields: {
      'stage1_name': ['Leads', 'New enquiries', 'Quotes sent'],
      'stage1_count': ['4', '9', '6'],
      'stage1_new': ['2', '3', '1'],
      'stage2_name': ['Paid — Ready to Start', 'Confirmed orders', 'Deposit received'],
      'stage2_count': ['23', '14', '31'],
      'stage2_new': ['3', '2', '5'],
      'stage3_name': ['In Progress', 'In Tailoring', 'Being Prepared'],
      'stage3_count': ['4', '7', '3'],
      'stage3_new': ['1', '2', '1'],
      'stage4_name': ['Ready to Send', 'Waiting for Feedback', 'Completed'],
      'stage4_count': ['3', '8', '12'],
      'revenue_total': ['\$3,780,113', '\$1,240,500', '\$842,900'],
      'revenue_today': ['\$604,355', '\$92,300', '\$38,600'],
    },
  ),
  _AppType(
    'products',
    'Product & Sales Tracker',
    ['Product list', 'Sales chart', 'Stock levels', 'Add product'],
    templateId: 'products',
    autoFields: {
      'owner_role': ['Owner', 'Shop Manager', 'Store Admin'],
      'product_count': ['6', '18', '42'],
      'sales_count': ['19', '54', '112'],
      'revenue': ['\$224', '\$1,840', '\$6,200'],
      'returns': ['4', '2', '9'],
      'chart_title': ["Today's sales", 'This week', 'Hourly sales'],
      'product1_name': ['Black Shine Shampoo', 'Sunsilk Conditioner', 'Herbal Soap Bar'],
      'product1_stock': ['340', '88', '210'],
      'product1_price': ['699', '850', '250'],
      'product2_name': ['Gaming Headphone', 'Wireless Earbuds', 'Bluetooth Speaker'],
      'product2_stock': ['88', '15,888', '46'],
      'product2_price': ['1000', '15888', '1200'],
      'product3_name': ['Daily Soap', 'Body Lotion', 'Hand Sanitizer'],
      'product3_stock': ['150', '60', '300'],
      'product3_price': ['699', '450', '150'],
    },
  ),
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
  final _studioKey = GlobalKey<LiveHtmlStudioState>();

  /// Code as it stood before the last AI change, so it can be reverted.
  String? _undoSnapshot;
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

  /// This build's folder under Projects › Applications once saved; later
  /// saves rewrite the same folder instead of making a new one.
  String? _projectId;
  String? _savedLabel;
  bool _saving = false;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startIntro());
  }

  Future<void> _startIntro() async {
    await _sayBot(
      "Hi! Let's build a simple mobile app you can preview in the browser. 📱\n\n"
      "What kind of app do you want?",
    );
    await _sayBot(
      // Circled numerals (U+2460-U+246D): one glyph per number past 10, where
      // keycap emoji would need two boxes and knock the column out of line.
      "① School Notes\n② Budget Tracker\n③ Quiz Game\n"
      "④ Habit Tracker\n⑤ To-Do List\n⑥ Local Market\n"
      "⑦ Farm / Crop Monitor\n⑧ Online Shop / Store\n"
      "⑨ Learning / Course App\n⑩ Shop Till / Sales Point\n"
      "⑪ Community / Social App\n⑫ Course Marketplace\n"
      "⑬ Order Pipeline\n⑭ Product & Sales Tracker\n\n"
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
    _AppType? chosen;

    // A typed number wins outright — substring matching cannot be used for
    // digits, because "10" contains "1" and would resolve to the first type.
    final digits = RegExp(r'^\s*(\d{1,2})\s*$').firstMatch(lower)?.group(1);
    final picked = digits == null ? null : int.tryParse(digits);
    if (picked != null && picked >= 1 && picked <= _appTypes.length) {
      chosen = _appTypes[picked - 1];
    }

    // Specific phrases first so "shop till" is not eaten by "shop".
    const matchers = <int, List<String>>{
      9: ['till', 'sales point', 'pos', 'cashier', 'register'],
      13: ['sales tracker', 'product tracker', 'inventory'],
      12: ['order pipeline', 'pipeline', 'orders'],
      11: ['course marketplace', 'marketplace', 'mentor'],
      10: ['social', 'community', 'feed'],
      6: ['farm', 'crop', 'agri', 'harvest', 'garden'],
      7: ['online shop', 'store', 'ecommerce', 'e-commerce', 'shop'],
      8: ['learn', 'course', 'lesson', 'study', 'education'],
      0: ['note', 'school notes'],
      1: ['budget', 'money', 'expense'],
      2: ['quiz', 'game'],
      3: ['habit'],
      4: ['todo', 'to-do', 'task'],
      5: ['market', 'sell'],
    };

    if (chosen == null) {
      for (final e in matchers.entries) {
        for (final k in e.value) {
          if (lower.contains(k)) {
            chosen = _appTypes[e.key];
            break;
          }
        }
        if (chosen != null) break;
      }
    }

    if (chosen == null) {
      await _sayBot("I didn't catch that. Type 1–14 or the app name.");
      return;
    }
    _appType = chosen;
    _choosingType = false;
    _choosingColor = true;
    await _sayBot("Great — ${chosen.name}! 🎨 Pick a color theme:");
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await _sayBot(
      "① Ocean Blue\n② Forest Green\n③ Royal Purple\n"
      "④ Sunset Orange\n⑤ Rose Pink\n\nType a number!",
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
      'Building your app…',
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
    if (_projectId != null) _saveToProjects(quiet: true);
  }

  // ── Project folder ───────────────────────────────────────────────────────

  String get _appTitle {
    final name = _answers['app_name']?.trim();
    if (name != null && name.isNotEmpty) return name;
    return _appType?.name ?? 'My app';
  }

  /// Writes the app as a full project (frontend + FastAPI/SQLite backend +
  /// docs) under Projects › Applications — the first time as a new folder,
  /// then into the same folder. [quiet] skips the snackbar for auto-saves.

  // Saves run one at a time. A save asked for while one is running is not
  // dropped: it marks [_saveAgain] and the running loop saves once more with
  // the latest code, so a quick style change right after Build still lands.
  Future<ProjectFolder?>? _saveInFlight;
  bool _saveAgain = false;
  bool _saveLoud = false;

  /// Saves the project (or queues one more save). The returned future
  /// completes after the newest code is on disk.
  Future<ProjectFolder?> _saveToProjects({bool quiet = false}) {
    _saveAgain = true;
    if (!quiet) _saveLoud = true;
    return _saveInFlight ??= _drainSaves().whenComplete(() => _saveInFlight = null);
  }

  Future<ProjectFolder?> _drainSaves() async {
    ProjectFolder? last;
    if (mounted) setState(() => _saving = true);
    try {
      while (_saveAgain && mounted) {
        _saveAgain = false;
        final loud = _saveLoud;
        _saveLoud = false;
        last = await _saveOnce(quiet: !loud) ?? last;
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    return last;
  }

  Future<ProjectFolder?> _saveOnce({required bool quiet}) async {
    if (_appType == null) return null;
    final html = _codeController.text;
    if (html.trim().isEmpty) return null;
    try {
      final intent = _currentIntent();
      final images = <String, Uint8List>{};
      final files = buildAppProject(
        title: _appTitle,
        html: html,
        appTypeId: intent.appTypeId,
        appTypeName: intent.appTypeName,
        themeColor: intent.themePrimary,
        features: intent.features,
        images: images,
      );
      final saved = await saveCreation(
        ref,
        kind: ProjectKind.application,
        title: _appTitle,
        files: files,
        binaryFiles: images,
        projectId: _projectId,
        source: 'app_builder',
        template: intent.appTypeId,
        templateName: intent.appTypeName,
        features: intent.features,
        answers: intent.answers,
      );
      if (!mounted) return saved?.folder;
      if (saved == null) {
        if (!quiet) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(tr(context, 'Create a learner profile to save projects.'))));
        }
        return null;
      }
      setState(() {
        _projectId = saved.folder.manifest.id;
        _savedLabel = saved.breadcrumb;
      });
      if (!quiet) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(trFill(context, 'Saved “{name}” to Projects', {'name': saved.breadcrumb})),
          action: SnackBarAction(
            label: tr(context, 'Open'),
            onPressed: () => context.push('/projects'),
          ),
        ));
      }
      return saved.folder;
    } catch (e) {
      debugPrint('app project save failed: $e');
      if (mounted && !quiet) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(tr(context, "Couldn't save your project. Try again."))));
      }
      return null;
    }
  }

  /// Swaps the screen for [html], keeps [undo] for the Undo snackbar,
  /// repaints and re-saves the project folder.
  void _replaceCode(String html, {required String undo}) {
    _undoSnapshot = undo;
    _codeController.text = html;
    _studioKey.currentState?.applyNow();
    if (_projectId != null) _saveToProjects(quiet: true);
  }

  Future<void> _addPictures() async {
    final before = _codeController.text;
    final updated = await showAddPicturesFlow(context, before);
    if (updated == null || !mounted) return;
    _replaceCode(updated, undo: before);
    showInstructionAppliedSnack(context, onUndo: _undoLastInstruction);
  }

  Future<void> _openStyle() async {
    final before = _codeController.text;
    final updated = await showStyleSheet(context, before);
    if (updated == null || !mounted) return;
    _replaceCode(updated, undo: before);
    showInstructionAppliedSnack(context, onUndo: _undoLastInstruction);
  }

  /// Shows the generated backend files (models, routes, tests) read-only.
  Future<void> _viewBackend() async {
    final folder = await _saveToProjects(quiet: true);
    if (folder == null || !mounted) return;
    await showProjectFilesSheet(context, folder, initialPrefix: 'backend/');
  }

  Future<void> _exportProject() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final folder = await _saveToProjects(quiet: true);
      if (folder == null || !mounted) return;
      await exportProjectZip(context, ref, folder);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _undoLastInstruction() async {
    final previous = _undoSnapshot;
    if (previous == null) return;
    _undoSnapshot = null;
    _codeController.text = previous;
    _studioKey.currentState?.applyNow();
    if (_projectId != null) await _saveToProjects(quiet: true);
  }

  /// Runs a plain-English restyle request ("center the text", "make it
  /// green") through the coder model and repaints the preview on success.
  Future<void> _applyInstruction(String instruction) async {
    if (_autocorrectBusy) return;
    final before = _codeController.text;
    if (before.trim().isEmpty) return;
    // Colour / font / size requests apply instantly, with no model call.
    final styled = tryQuickStyleInstruction(before, instruction);
    if (styled != null) {
      _replaceCode(styled, undo: before);
      showInstructionAppliedSnack(context, onUndo: _undoLastInstruction);
      return;
    }
    final coderOk = await promptAndFetchCoderPackage(context, ref);
    if (!coderOk || !mounted) return;
    setState(() => _autocorrectBusy = true);
    try {
      final engine = await ref.read(programmingEngineProvider.future);
      // Pictures go to the model as short placeholders, not megabytes of
      // base64 that would crowd out the page itself.
      final masked = maskEmbeddedImages(before);
      final edited = await applyCodeInstruction(
        source: masked.text,
        instruction: instruction,
        kind: CodeAutocorrectKind.html,
        engine: engine,
      );
      final fixed = edited == null ? null : masked.restore(edited);
      if (!mounted) return;
      if (fixed == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(context, "Couldn't apply that — try describing it a different way."),
            ),
          ),
        );
        return;
      }
      _replaceCode(fixed, undo: before);
      if (!mounted) return;
      showInstructionAppliedSnack(context, onUndo: _undoLastInstruction);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'Something went wrong. Please try again.'))),
      );
    } finally {
      if (mounted) setState(() => _autocorrectBusy = false);
    }
  }

  /// Maps the student's app name, purpose, theme, and chosen features onto
  /// the screen template for this app type. Every value is HTML-escaped; the
  /// feature list is markup this method builds itself, so it goes in raw.
  Future<String> _assembleAppHtml(AppBuildIntent intent) async {
    final type = _appType!;
    var html = await rootBundle
        .loadString('assets/templates/apps/${type.templateId}.html');

    final appName = intent.appName.trim().isEmpty ? 'My App' : intent.appName;
    final tokens = <String, String>{
      'app_name': appName,
      'type_name': type.name,
      'purpose': intent.purpose.trim().isEmpty ? type.name : intent.purpose,
      'primary': intent.themePrimary,
      'initial': appName.trim().substring(0, 1).toUpperCase(),
      'stat1': '3',
      'stat2': '12',
      'stat3': '48',
      for (final entry in type.autoFields.entries)
        entry.key: _pick(entry.value),
    };

    for (final entry in tokens.entries) {
      html = html.replaceAll('{{${entry.key}}}', escapeHtml(entry.value));
    }

    final features = intent.features.isEmpty
        ? ['Home screen']
        : intent.features;
    final list = StringBuffer('<ul>');
    for (final feature in features) {
      list.write('<li>${escapeHtml(feature)}</li>');
    }
    list.write('</ul>');
    return html.replaceAll('{{features}}', list.toString());
  }

  Future<void> _buildApp() async {
    if (_appType == null) return;
    if (!mounted) return;

    setState(() {
      _building = true;
      _buildNote = tr(context, 'Building your app…');
      // A fresh build is a different app from whatever was last saved.
      _projectId = null;
      _savedLabel = null;
    });

    final intent = _currentIntent();
    final html = await _assembleAppHtml(intent);

    if (!mounted) return;
    _codeController.text = html;

    final ready = tr(
      context,
      'Your app preview is ready! 🎉 Toggle Preview / Code to view or edit.',
    );

    setState(() {
      _messages.add(_ChatMsg(ready, true));
      _building = false;
      _showStudio = true;
      _buildNote = '';
    });
    _scrollDown();
    // Every build is a project: saved straight away into Projects ›
    // Applications, with its own backend.
    await _saveToProjects();
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
          TextButton(
            onPressed: () => context.push('/applab'),
            child: Text(tr(context, 'Lessons')),
          ),
          if (_showStudio) ...[
            PopupMenuButton<String>(
              tooltip: tr(context, 'More'),
              enabled: !_exporting,
              icon: _exporting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.more_vert),
              onSelected: (value) {
                if (value == 'backend') _viewBackend();
                if (value == 'export') _exportProject();
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'backend',
                  child: Row(children: [
                    const Icon(Icons.dns_outlined, size: 18),
                    const SizedBox(width: 10),
                    Text(tr(context, 'View project files')),
                  ]),
                ),
                PopupMenuItem(
                  value: 'export',
                  child: Row(children: [
                    const Icon(Icons.ios_share_outlined, size: 18),
                    const SizedBox(width: 10),
                    Text(tr(context, 'Export project (.zip)')),
                  ]),
                ),
              ],
            ),
            TextButton(
              onPressed: () => setState(() => _showStudio = false),
              child: Text(tr(context, 'Back to chat')),
            ),
          ],
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
                    ? 'Edit the code on the left — the preview on the right updates as you type. Use Reload or Full screen in the preview bar.'
                    : 'Answer the prompts to record features. Build makes your app, '
                        'then opens Preview Layout | View Source Code.',
              ),
              style: const TextStyle(fontSize: 12, height: 1.35),
            ),
          ),
          if (_showStudio) ...[
            ProjectToolsBar(
              savedLabel: _savedLabel,
              saving: _saving,
              onSave: _saveToProjects,
              onPictures: _addPictures,
              onStyle: _openStyle,
              onOpenProjects: () => context.push('/projects'),
            ),
            Expanded(
              child: LiveHtmlStudio(
                key: _studioKey,
                controller: _codeController,
                onApply: _applyCodeEdits,
                toolbar: CodeInstructionBar(
                  busy: _autocorrectBusy,
                  onSubmit: _applyInstruction,
                ),
              ),
            ),
          ] else
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
