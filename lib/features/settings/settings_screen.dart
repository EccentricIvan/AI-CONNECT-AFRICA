import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../teacher/teacher_pin_screen.dart';
import '../../ai_core/providers/ai_provider.dart';
import '../../ai_core/translate/chat_languages.dart';
import '../../ai_core/translate/supported_languages.dart';
import '../../core/app_info_provider.dart';
import 'fetch_packages_tile.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_provider.dart';
import '../../db/providers/db_provider.dart';
import '../../l10n/app_locale.dart';
import '../../l10n/language_provider.dart';
import '../../services/model_fetch_service.dart';
import '../../shared/widgets/responsive.dart';
import '../../shared/widgets/studio_page.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studentAsync = ref.watch(activeStudentProvider);
    final modelAsync = ref.watch(modelInfoProvider);
    final packageInfoAsync = ref.watch(packageInfoProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
appBar: StudioAppBar(
        title: tr(context, 'Settings'),
        subtitle: tr(context, 'Profile, AI model & preferences'),
        icon: Icons.settings_rounded,
        iconColor: const Color(0xFF6B8499),
      ),
      body: MaxWidth(
        maxWidth: 760,
        child: ListView(
          children: [
            // ── System Core Configuration ────────────────────────────────────
            _Section('System Core Configuration', [
              const FetchPackagesTile(),
              ref.watch(aiStatusProvider).when(
                loading: () => ListTile(
                  leading: const Icon(Icons.auto_awesome, color: AppColors.primary),
                  title: Text(tr(context, 'Checking workspace…')),
                ),
                error: (_, __) => ListTile(
                  leading: const Icon(Icons.auto_awesome, color: Colors.orange),
                  title: const Text('Workspace check incomplete'),
                  subtitle: const Text('You can still explore the app.'),
                ),
                data: (status) => ListTile(
                  leading: Icon(
                    status.isDemo ? Icons.info_outline : Icons.verified_outlined,
                    color: status.isDemo
                        ? Colors.orange
                        : AppColors.teachColor,
                  ),
                  title: Text(
                    status.isDemo
                        ? tr(context, 'Demo mode')
                        : (status.backendLabel?.startsWith('Cloud') == true
                            ? 'Cloud assistant ready'
                            : 'Classroom assistant ready'),
                  ),
                  subtitle: Text(
                    status.isDemo
                        ? 'Sample answers until setup is finished in this screen.'
                        : tr(context, 'Ready on this device.'),
                  ),
                  isThreeLine: status.isDemo,
                  trailing: Icon(
                    status.isDemo ? Icons.warning_amber : Icons.check_circle,
                    color: status.isDemo ? Colors.orange : AppColors.teachColor,
                  ),
                ),
              ),
              modelAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (info) => ListTile(
                  leading: Icon(
                    Icons.inventory_2_outlined,
                    color: info.isReady ? AppColors.teachColor : Colors.orange,
                  ),
                  title: const Text('Workspace Optimization'),
                  subtitle: Text(
                    info.isReady
                        ? 'Packages ready on this device'
                        : 'Packages not installed yet — use Install Packages above',
                  ),
                  trailing: info.isReady
                      ? const Icon(
                          Icons.check_circle,
                          color: AppColors.teachColor,
                        )
                      : const Icon(Icons.warning_amber, color: Colors.orange),
                ),
              ),
              ListTile(
                leading: Icon(
                  Icons.info_outline,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                title: Text(tr(context, 'How AI works here')),
                subtitle: const Text(
                  'Answers are generated on this device. Chat uses the '
                  'language you chose. If setup is incomplete, you still get '
                  'sample replies so you can explore the app.',
                ),
                isThreeLine: true,
              ),
            ]),

            // ── Learning language ────────────────────────────────────────────
            _Section(tr(context, 'Learning language'), [
              // Drives labels and model routing together: appLanguageProvider
              // is the same value the AfriSLM round-trip reads. The choice is
              // written to SharedPreferences so it survives Install Packages
              // and an app restart on Android and Windows.
              Builder(builder: (context) {
                final language = ref.watch(appLanguageProvider);
                return ListTile(
                  leading: const Icon(Icons.language, color: AppColors.primary),
                  title: Text(tr(context, 'Learning language')),
                  subtitle: Text(
                    'Chat uses ${languageName(language)}',
                  ),
                  trailing: DropdownButton<String>(
                    value: coercePickableLanguage(language),
                    underline: const SizedBox.shrink(),
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.of(context).textPrimary,
                    ),
                    items: [
                      for (final lang in pickableLanguages)
                        DropdownMenuItem(
                          value: lang.code,
                          child: Text(lang.name),
                        ),
                    ],
                    onChanged: (code) {
                      if (code == null) return;
                      ref
                          .read(languageOverrideProvider.notifier)
                          .setLanguage(code);
                    },
                  ),
                );
              }),
              const _TranslateModelTile(),
              ListTile(
                leading: const Icon(Icons.info_outline, color: Colors.grey),
                title: Text(tr(context, 'How chat language works')),
                subtitle: const Text(
                  'Ask in your learning language. Replies come back in the '
                  'same language. Chat works this way on Home and in Learn, '
                  'Create, and Apply.',
                ),
                isThreeLine: true,
              ),
            ]),

            // ── Student ───────────────────────────────────────────────────────
            _Section('Student Profile', [
              studentAsync.when(
                loading: () => const ListTile(title: Text('Loading…')),
                error: (_, __) => const ListTile(title: Text('Error')),
                data: (student) => ListTile(
                  leading: Icon(
                    Icons.person_outline,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  title: Text(student?.name ?? 'No profile'),
                  subtitle: Text(
                    student != null
                        ? [
                            if (student.grade != null) student.grade!,
                            'Style: ${student.learningStyle}',
                            '${student.totalPoints} points',
                          ].join(' · ')
                        : 'Complete onboarding to start',
                  ),
                ),
              ),
              ListTile(
                leading: Icon(
                  Icons.edit_outlined,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                title: Text(tr(context, 'Edit profile')),
                subtitle: const Text(
                  'Update your interests and learning style',
                ),
                onTap: () => context.go('/onboarding'),
                trailing: Icon(
                  Icons.chevron_right,
                  color: Theme.of(context).hintColor,
                ),
              ),
              ListTile(
                leading: Icon(
                  Icons.switch_account_outlined,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                title: Text(tr(context, 'Switch learner')),
                subtitle: Text(
                  tr(context, 'Hand this device to another learner'),
                ),
                onTap: () => context.push('/learners'),
                trailing: Icon(
                  Icons.chevron_right,
                  color: Theme.of(context).hintColor,
                ),
              ),
            ]),

            // ── Streak & Points ───────────────────────────────────────────────
            studentAsync.when(
              data: (student) => student != null
                  ? _Section('Progress', [
                      ListTile(
                        leading: const Icon(
                          Icons.local_fire_department,
                          color: Colors.orange,
                        ),
                        title: Text('${student.streakDays} day streak'),
                        subtitle: const Text(
                          'Keep learning daily to grow your streak',
                        ),
                      ),
                      ListTile(
                        leading: const Icon(Icons.stars, color: Colors.amber),
                        title: Text('${student.totalPoints} points earned'),
                        subtitle: const Text(
                          'Points grow as you complete lessons and earn badges',
                        ),
                      ),
                    ])
                  : const SizedBox.shrink(),
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),

            // ── Theme ────────────────────────────────────────────────────────
            _Section('Appearance', [
              ListTile(
                leading: Icon(
                  Icons.brightness_6,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                title: Text(tr(context, 'Theme')),
                subtitle: Text(
                  ref.watch(themeModeProvider) == ThemeMode.dark
                      ? 'Dark'
                      : ref.watch(themeModeProvider) == ThemeMode.light
                          ? 'Light'
                          : 'System',
                ),
                trailing: SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.light,
                      icon: Icon(Icons.light_mode, size: 18),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      icon: Icon(Icons.dark_mode, size: 18),
                    ),
                    ButtonSegment(
                      value: ThemeMode.system,
                      icon: Icon(Icons.settings_suggest, size: 18),
                    ),
                  ],
                  selected: {ref.watch(themeModeProvider)},
                  onSelectionChanged: (s) =>
                      ref.read(themeModeProvider.notifier).set(s.first),
                  showSelectedIcon: false,
                ),
              ),
            ]),

            // ── App ──────────────────────────────────────────────────────────
            _Section('App', [
              ListTile(
                leading: Icon(
                  Icons.info_outline,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                title: Text(tr(context, 'Version')),
                subtitle: Text(
                  packageInfoAsync.when(
                    data: (info) => 'Version ${info.version} (build ${info.buildNumber})',
                    loading: () => 'Loading…',
                    error: (_, __) => 'Unknown',
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.wifi_off, color: AppColors.primary),
                title: Text(tr(context, 'Offline mode')),
                subtitle: Text(tr(context, '100% offline — no internet required')),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.teachColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Active',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.teachColor,
                    ),
                  ),
                ),
              ),
            ]),

            // ── Admin ────────────────────────────────────────────────────────
            _Section('Administration', [
              ListTile(
                leading: Icon(
                  Icons.lock_outline,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                title: const Text('Teacher PIN'),
                subtitle: const Text(
                  'Keep learners out of the Teacher and Admin areas',
                ),
                onTap: () => showTeacherPinSettings(context, ref),
                trailing: Icon(
                  Icons.chevron_right,
                  color: Theme.of(context).hintColor,
                ),
              ),
              ListTile(
                leading: Icon(
                  Icons.groups_outlined,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                title: const Text('Teacher dashboard'),
                subtitle: const Text(
                  'See learners on this device, topic progress, and sessions',
                ),
                onTap: () => context.go('/teacher'),
                trailing: Icon(
                  Icons.chevron_right,
                  color: Theme.of(context).hintColor,
                ),
              ),
              ListTile(
                leading: Icon(
                  Icons.admin_panel_settings,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                title: const Text('Admin dashboard'),
                subtitle: const Text(
                  'Device info, model status, profiles, update management',
                ),
                onTap: () => context.go('/admin'),
                trailing: Icon(
                  Icons.chevron_right,
                  color: Theme.of(context).hintColor,
                ),
              ),
            ]),

            // ── Danger zone ───────────────────────────────────────────────────
            _Section('Data', [
              ListTile(
                leading: const Icon(Icons.delete_forever, color: Colors.red),
                title: const Text(
                  'Reset all data',
                  style: TextStyle(color: Colors.red),
                ),
                subtitle: const Text(
                  'Deletes student profile, progress, and sessions',
                ),
                onTap: () => _confirmReset(context, ref),
              ),
            ]),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  void _confirmReset(BuildContext context, WidgetRef ref) {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset all data?'),
        content: const Text(
          'This permanently deletes your student profile, all progress, paths, badges, and session history. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete everything'),
          ),
        ],
      ),
    ).then((confirmed) async {
      if (confirmed != true) return;
      // Go to onboarding which will recreate the profile
      if (context.mounted) context.go('/onboarding');
    });
  }
}

/// Install-from-file for the optional regional language pack.
class _TranslateModelTile extends ConsumerStatefulWidget {
  const _TranslateModelTile();

  @override
  ConsumerState<_TranslateModelTile> createState() => _TranslateModelTileState();
}

class _TranslateModelTileState extends ConsumerState<_TranslateModelTile> {
  bool _busy = false;
  double? _progress;
  String? _statusMessage;

  Future<void> _installFromFile() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select a language package file',
      type: FileType.any,
    );
    final path = result?.files.single.path;
    if (path == null) return;

    setState(() {
      _busy = true;
      _progress = 0;
      _statusMessage = 'Setting up regional workspace...';
    });

    try {
      final manager = ref.read(translateModelManagerProvider);
      await manager.installFromFile(
        path,
        onProgress: (p) {
          if (mounted && (p - (_progress ?? 0) >= 0.01 || p >= 1)) {
            setState(() {
              _progress = p;
              _statusMessage = ModelFetchService.whiteLabelStatus(
                p,
                connecting: p <= 0,
              );
            });
          }
        },
      );

      ref.invalidate(translateModelInfoProvider);
      ref.invalidate(translateEngineLoadedProvider);
      ref.invalidate(translationPipelineProvider);

      if (mounted) {
        setState(() => _statusMessage = null);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Language package ready on this device.')),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _statusMessage = null);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not finish language package setup. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final modelAsync = ref.watch(translateModelInfoProvider);
    final engineAsync = ref.watch(translateEngineLoadedProvider);

    return modelAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (info) {
        final ready = info.isReady && (engineAsync.valueOrNull != null);
        String subtitle;
        if (_busy) {
          subtitle = _statusMessage ?? 'Optimizing formula drivers...';
        } else if (ready) {
          subtitle = 'Installed';
        } else if (info.isReady) {
          subtitle = 'Installed — getting ready…';
        } else {
          subtitle = 'Not installed — chat stays in English';
        }

        return ListTile(
          leading: Icon(
            Icons.translate_outlined,
            color: ready ? AppColors.teachColor : Colors.orange,
          ),
          title: const Text('Regional language pack'),
          subtitle: Text(subtitle),
          trailing: _busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : TextButton(
                  onPressed: _installFromFile,
                  child: Text(info.isReady ? 'Reinstall' : 'Install from file…'),
                ),
        );
      },
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.children);
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
          child: Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
              letterSpacing: 0.8,
            ),
          ),
        ),
        ...children,
        const Divider(height: 1),
      ],
    );
  }
}
