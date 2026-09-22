import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../certificates/certificate_generator.dart';
import '../../core/theme/app_colors.dart';
import '../../db/otic_database.dart';
import '../../db/providers/db_provider.dart';
import '../../features/learn/path/path_provider.dart';
import '../../features/learn/path/path_models.dart';
import '../../l10n/app_locale.dart';
import '../../shared/widgets/responsive.dart';
import '../../shared/widgets/studio_page.dart';

class CertificatesScreen extends ConsumerWidget {
  const CertificatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studentAsync = ref.watch(activeStudentProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
appBar: StudioAppBar(
        title: tr(context, 'Certificates'),
        subtitle: tr(context, 'Celebrate completed paths'),
        icon: Icons.workspace_premium_rounded,
        iconColor: AppColors.accentViolet,
        showBack: true,
      ),
      body: studentAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (student) {
          if (student == null) {
            return const Center(child: Text('No student profile found.'));
          }
          return _CertsBody(student: student);
        },
      ),
    );
  }
}

class _CertsBody extends ConsumerStatefulWidget {
  const _CertsBody({required this.student});
  final Student student;

  @override
  ConsumerState<_CertsBody> createState() => _CertsBodyState();
}

class _CertsBodyState extends ConsumerState<_CertsBody> {
  bool _generating = false;
  List<File> _savedFiles = [];

  @override
  void initState() {
    super.initState();
    _loadSavedCerts();
  }

  Future<void> _loadSavedCerts() async {
    final dir = await getApplicationDocumentsDirectory();
    final certsDir = Directory(
        '${dir.path}${Platform.pathSeparator}otic_certificates');
    if (await certsDir.exists()) {
      final files = certsDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.pdf'))
          .toList()
        ..sort((a, b) => b.path.compareTo(a.path));
      if (mounted) setState(() => _savedFiles = files);
    }
  }

  Future<void> _generate(ParsedPath path) async {
    if (_generating) return;
    setState(() => _generating = true);
    try {
      final result = await CertificateGenerator.generate(
        studentName: widget.student.name,
        pathTitle: path.title,
        topic: path.topic,
      );
      await _loadSavedCerts();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Certificate saved: ${result.fileName}'),
          backgroundColor: AppColors.teachColor,
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'Share',
            textColor: Colors.white,
            onPressed: () => _share(File(result.filePath)),
          ),
        ));
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _share(File file) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        text: 'My certificate from AI Connect Africa',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pathsAsync = ref.watch(studentPathsProvider);

    return MaxWidth(
        maxWidth: 900,
        child: CustomScrollView(
      slivers: [
        // Earned certificates section
        if (_savedFiles.isNotEmpty) ...[
          const SliverToBoxAdapter(
            child: _SectionTitle('Your Certificates'),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (_, i) => _CertTile(
                file: _savedFiles[i],
                onShare: () => _share(_savedFiles[i]),
              ),
              childCount: _savedFiles.length,
            ),
          ),
        ],

        // Generate from completed paths
        const SliverToBoxAdapter(
          child: _SectionTitle('Generate a Certificate'),
        ),
        SliverToBoxAdapter(
          child: pathsAsync.when(
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (_, __) => const SizedBox.shrink(),
            data: (rows) {
              final completed = rows
                  .map(parsedFromRow)
                  .where((p) => p.progressFraction == 1.0)
                  .toList();

              if (completed.isEmpty) {
                return _EmptyState(
                    hasAny: rows.isNotEmpty,
                    savedCount: _savedFiles.length);
              }

              return Column(
                children: completed.map((p) => _PathCertCard(
                      path: p,
                      generating: _generating,
                      onGenerate: () => _generate(p),
                    )).toList(),
              );
            },
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 40)),
      ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 12),
      child: StudioSectionHeader(title: tr(context, title)),
    );
  }
}

class _CertTile extends StatelessWidget {
  const _CertTile({required this.file, required this.onShare});
  final File file;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final ac = AppColors.of(context);
    final name = file.path.split(Platform.pathSeparator).last;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: StudioCard(
        onTap: onShare,
        child: Row(
          children: [
            const StudioIconChip(
              icon: Icons.workspace_premium_rounded,
              color: AppColors.accentViolet,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name.replaceAll('_', ' ').replaceAll('.pdf', ''),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: ac.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tr(context, 'Tap to share'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: ac.textSecondary),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.ios_share_rounded,
                  color: AppColors.accentViolet, size: 20),
              tooltip: tr(context, 'Share certificate'),
              onPressed: onShare,
            ),
          ],
        ),
      ),
    );
  }
}

class _PathCertCard extends StatelessWidget {
  const _PathCertCard(
      {required this.path,
      required this.generating,
      required this.onGenerate});
  final ParsedPath path;
  final bool generating;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    final ac = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: StudioCard(
        accent: AppColors.accentOrange,
        child: Row(
          children: [
            const StudioIconChip(
              icon: Icons.emoji_events_rounded,
              color: AppColors.accentOrange,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(path.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: ac.textPrimary)),
                  const SizedBox(height: 2),
                  Text(
                      trFill(context, '{count} lessons completed',
                          {'count': '${path.totalLessons}'}),
                      style:
                          TextStyle(fontSize: 12, color: ac.textSecondary)),
                ],
              ),
            ),
            generating
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : FilledButton(
                    onPressed: onGenerate,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.secondary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      minimumSize: Size.zero,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(99)),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(tr(context, 'Generate PDF'),
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasAny, required this.savedCount});
  final bool hasAny;
  final int savedCount;

  @override
  Widget build(BuildContext context) {
    final ac = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        children: [
          Icon(Icons.workspace_premium_rounded, size: 56, color: ac.textHint),
          const SizedBox(height: 16),
          Text(
            tr(
              context,
              savedCount > 0
                  ? 'No new paths to certify'
                  : 'No certificates yet',
            ),
            style: TextStyle(
                fontFamily: 'Saira',
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: ac.textPrimary),
          ),
          const SizedBox(height: 8),
          Text(
            tr(
              context,
              hasAny
                  ? 'Complete all 12 lessons in a learning path to earn a certificate.'
                  : 'Start a learning path and complete all lessons to earn your first certificate.',
            ),
            textAlign: TextAlign.center,
            style: TextStyle(color: ac.textSecondary, height: 1.5),
          ),
        ],
      ),
    );
  }
}
