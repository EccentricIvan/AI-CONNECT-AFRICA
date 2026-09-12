import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../ai_core/providers/ai_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../l10n/app_locale.dart';
import '../../shared/coding/code_autocorrect.dart';
import '../../shared/widgets/code_autocorrect_button.dart';
import '../../shared/widgets/html_preview.dart';
import '../../shared/widgets/studio_page.dart';
import 'app_build_controller.dart';
import 'app_build_intent.dart';

/// Interactive App Dev Lab: feature picker → Qwen 1.5B Build → Preview/Code.
class AppDevLabScreen extends ConsumerStatefulWidget {
  const AppDevLabScreen({super.key});

  @override
  ConsumerState<AppDevLabScreen> createState() => _AppDevLabScreenState();
}

class _AppDevLabScreenState extends ConsumerState<AppDevLabScreen> {
  String _typeId = kAppLabTypes.first.id;
  String _themeId = kAppLabThemes.first.id;
  final Set<String> _features = {};
  final _nameCtrl = TextEditingController();
  final _purposeCtrl = TextEditingController();
  final _audienceCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  var _autocorrectBusy = false;
  var _previewEpoch = 0;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _purposeCtrl.dispose();
    _audienceCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  AppLabType get _type => appLabTypeById(_typeId) ?? kAppLabTypes.first;
  AppLabTheme get _theme => appLabThemeById(_themeId) ?? kAppLabThemes.first;

  AppBuildIntent _lockIntent() {
    final opts = _type.featureOptions;
    final selected =
        _features.isEmpty ? opts.take(2).toList() : _features.toList();
    return AppBuildIntent(
      appTypeId: _type.id,
      appTypeName: _type.name,
      themeId: _theme.id,
      themeName: _theme.name,
      themePrimary: _theme.primaryHex,
      answers: {
        'app_name': _nameCtrl.text.trim().isEmpty
            ? _type.name
            : _nameCtrl.text.trim(),
        'purpose': _purposeCtrl.text.trim(),
        'audience': _audienceCtrl.text.trim(),
      },
      features: selected,
    );
  }

  Future<void> _onBuild() async {
    final intent = _lockIntent();
    await ref.read(appBuildControllerProvider.notifier).buildFromIntent(intent);
    final ready = ref.read(appBuildControllerProvider);
    if (!mounted) return;
    _codeCtrl.text = ready.previewHtml;
    setState(() => _previewEpoch++);
  }

  Future<void> _autocorrect() async {
    if (_autocorrectBusy) return;
    final before = _codeCtrl.text;
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
      _codeCtrl.text = fixed;
    } catch (_) {
      if (!mounted) return;
      _codeCtrl.text =
          applyHeuristicAutocorrect(before, CodeAutocorrectKind.html);
    } finally {
      if (mounted) setState(() => _autocorrectBusy = false);
    }
  }

  void _apply() {
    ref.read(appBuildControllerProvider.notifier).applyCodeEdits(_codeCtrl.text);
    setState(() => _previewEpoch++);
  }

  @override
  Widget build(BuildContext context) {
    final studio = ref.watch(appBuildControllerProvider);
    final building = studio.phase == AppBuildPhase.building;
    final ready =
        studio.phase == AppBuildPhase.ready && studio.previewHtml.isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.phone_android, size: 20, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(tr(context, 'App Dev Lab')),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => context.push('/appchat'),
            child: Text(tr(context, 'Chat builder')),
          ),
          const StudioDrawerButton(),
          if (ready)
            TextButton(
              onPressed: () {
                ref.read(appBuildControllerProvider.notifier).reset();
              },
              child: Text(tr(context, 'Edit features')),
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
                ready
                    ? 'Simple Browser on the right updates as you edit Code — '
                        'all inside the app (no external browser).'
                    : 'Pick app type, theme, and features. Build runs the coding '
                        'model, then opens an in-app Code | Preview studio.',
              ),
              style: const TextStyle(fontSize: 12, height: 1.35),
            ),
          ),
          if (building)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      studio.buildNote.isEmpty
                          ? tr(context, 'Building your app...')
                          : studio.buildNote,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: ready
                ? LiveHtmlStudio(
                    key: ValueKey('app-studio-$_previewEpoch'),
                    controller: _codeCtrl,
                    initialHtml: studio.previewHtml,
                    onApply: _apply,
                    toolbar: Row(
                      children: [
                        CodeAutocorrectButton(
                          busy: _autocorrectBusy,
                          onPressed: _autocorrect,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _apply,
                            icon: const Icon(Icons.play_arrow),
                            label: Text(tr(context, 'Apply Changes')),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: building ? null : _onBuild,
                          icon: const Icon(Icons.refresh, size: 18),
                          label: Text(tr(context, 'Rebuild')),
                        ),
                      ],
                    ),
                  )
                : _FeaturePicker(
                    typeId: _typeId,
                    themeId: _themeId,
                    features: _features,
                    nameCtrl: _nameCtrl,
                    purposeCtrl: _purposeCtrl,
                    audienceCtrl: _audienceCtrl,
                    building: building,
                    onType: (id) => setState(() {
                      _typeId = id;
                      _features.clear();
                    }),
                    onTheme: (id) => setState(() => _themeId = id),
                    onToggleFeature: (f) => setState(() {
                      if (_features.contains(f)) {
                        _features.remove(f);
                      } else {
                        _features.add(f);
                      }
                    }),
                    onBuild: building ? null : _onBuild,
                  ),
          ),
        ],
      ),
    );
  }
}

class _FeaturePicker extends StatelessWidget {
  const _FeaturePicker({
    required this.typeId,
    required this.themeId,
    required this.features,
    required this.nameCtrl,
    required this.purposeCtrl,
    required this.audienceCtrl,
    required this.building,
    required this.onType,
    required this.onTheme,
    required this.onToggleFeature,
    required this.onBuild,
  });

  final String typeId;
  final String themeId;
  final Set<String> features;
  final TextEditingController nameCtrl;
  final TextEditingController purposeCtrl;
  final TextEditingController audienceCtrl;
  final bool building;
  final ValueChanged<String> onType;
  final ValueChanged<String> onTheme;
  final ValueChanged<String> onToggleFeature;
  final VoidCallback? onBuild;

  @override
  Widget build(BuildContext context) {
    final type = appLabTypeById(typeId) ?? kAppLabTypes.first;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          tr(context, 'Application type'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in kAppLabTypes)
              ChoiceChip(
                avatar: Icon(t.icon, size: 16),
                label: Text(t.name),
                selected: typeId == t.id,
                onSelected: building ? null : (_) => onType(t.id),
              ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          tr(context, 'Visual style'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final th in kAppLabThemes)
              ChoiceChip(
                avatar: CircleAvatar(backgroundColor: th.primary, radius: 8),
                label: Text(th.name),
                selected: themeId == th.id,
                onSelected: building ? null : (_) => onTheme(th.id),
              ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          tr(context, 'Core app details'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: nameCtrl,
          enabled: !building,
          decoration: InputDecoration(
            labelText: tr(context, 'App name'),
            hintText: 'e.g. StudySpark',
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: purposeCtrl,
          enabled: !building,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: tr(context, 'Purpose'),
            hintText: 'e.g. Helps students track daily tasks',
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: audienceCtrl,
          enabled: !building,
          decoration: InputDecoration(
            labelText: tr(context, 'Who is it for?'),
            hintText: 'e.g. Secondary school students',
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          tr(context, 'Features'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        ...type.featureOptions.map(
          (f) => CheckboxListTile(
            value: features.contains(f),
            onChanged: building ? null : (_) => onToggleFeature(f),
            title: Text(f),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: onBuild,
          icon: const Icon(Icons.auto_awesome),
          label: Text(tr(context, 'Build Application')),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: building
              ? null
              : () => context.push('/learn/subject/app_development'),
          child: Text(tr(context, 'Open curriculum lessons')),
        ),
      ],
    );
  }
}
