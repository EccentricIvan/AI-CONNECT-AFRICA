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
        iconColor: const Color(0xFF7B6CF6),
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
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 15,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }
}

class _CertTile extends StatelessWidget {
  const _CertTile({required this.file, required this.onShare});
  final File file;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final name = file.path.split(Platform.pathSeparator).last;
    return ListTile(
      onTap: onShare,
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: AppColors.secondary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.workspace_premium,
            color: AppColors.secondary, size: 22),
      ),
      title: Text(
        name.replaceAll('_', ' ').replaceAll('.pdf', ''),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        'Tap to share',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.share, color: AppColors.secondary, size: 20),
        tooltip: 'Share certificate',
        onPressed: onShare,
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
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        children: [
          const Icon(Icons.emoji_events, color: Colors.amber, size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(path.title,
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface)),
                Text('${path.totalLessons} lessons completed',
                    style: TextStyle(
                        fontSize: 12, color: Theme.of(context).hintColor)),
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
                        horizontal: 14, vertical: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Generate PDF',
                      style: TextStyle(fontSize: 12)),
                ),
        ],
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
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        children: [
          Icon(Icons.workspace_premium,
              size: 56, color: Theme.of(context).hintColor),
          const SizedBox(height: 16),
          Text(
            savedCount > 0
                ? 'No new paths to certify'
                : 'No certificates yet',
            style: TextStyle(
                fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface),
          ),
          const SizedBox(height: 8),
          Text(
            hasAny
                ? 'Complete all 12 lessons in a learning path to earn a certificate.'
                : 'Start a learning path and complete all lessons to earn your first certificate.',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.5),
          ),
        ],
      ),
    );
  }
}
