import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../ai_core/providers/ai_provider.dart';
import '../../ai_core/tutor/programming_topic.dart';
import '../../app.dart';
import '../../db/providers/db_provider.dart';
import '../../features/achievements/achievements_screen.dart';
import '../../features/admin/admin_screen.dart';
import '../../features/certificates/certificates_screen.dart';
import '../../features/create/create_screen.dart';
import '../../features/app_dev_lab/app_chat_builder_screen.dart';
import '../../features/app_dev_lab/app_dev_lab_screen.dart';
import '../../features/curriculum_browser/lesson_screen.dart';
import '../../features/python_lab/python_lab_screen.dart';
import '../../features/curriculum_browser/subjects_screen.dart';
import '../../features/curriculum_browser/units_screen.dart';
import '../../features/learn/learn_screen.dart';
import '../../features/learn/path/path_detail_screen.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/practice/practice_screen.dart';
import '../../features/projects/projects_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/teacher/lesson_materials_screen.dart';
import '../../features/teacher/teacher_dashboard_screen.dart';
import '../../features/site_builder/site_chat_builder_screen.dart';
import '../../features/web_dev_lab/web_dev_lab_screen.dart';
import '../../features/website/website_builder_screen.dart';
import '../../screens/package_fetch_screen.dart';
import '../../shared/widgets/app_shell.dart';

final _rootKey = GlobalKey<NavigatorState>();
final _shellKey = GlobalKey<NavigatorState>();

/// Provider-aware router so the redirect can read [hasProfileProvider].
final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/',
    redirect: (context, state) async {
      if (state.matchedLocation == '/onboarding') return null;

      // Fast path: SharedPreferences is written synchronously by onboarding
      // before it navigates away, so a name here means onboarding is done —
      // no need to wait on the (slower, background-written) database.
      final prefs = await SharedPreferences.getInstance();
      final name = prefs.getString('student_name');
      if (name != null && name.isNotEmpty) return null;

      // On web there's no database — SharedPreferences is authoritative.
      if (kIsWeb) return '/onboarding';

      try {
        final hasProfile = await ref.read(hasProfileProvider.future)
            .timeout(const Duration(seconds: 3));
        if (!hasProfile) return '/onboarding';
      } catch (_) {
        return '/onboarding';
      }
      return null;
    },
    routes: [
      // Onboarding is outside the shell (no nav bar/sidebar)
      GoRoute(
        path: '/onboarding',
        builder: (_, __) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/packages',
        builder: (_, __) => const PackageFetchScreen(),
      ),
      ShellRoute(
        navigatorKey: _shellKey,
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          // Home is the AI chat workspace (formerly `/chat`).
          GoRoute(path: '/', builder: (_, state) {
            final topic = state.uri.queryParameters['topic'];
            final sectionParam = state.uri.queryParameters['section'];
            final subject = state.uri.queryParameters['subject'];
            final section = topic != null || sectionParam == 'learn'
                ? ChatSection.learn
                : ChatSection.wholesomeChat;
            final programming = isProgrammingSubjectId(subject) ||
                looksLikeProgramming(topic ?? '');
            // Skip ModelGate on web only — the browser build can't run a
            // local model at all. Android/Windows/Linux need the AfriSLM GGUF.
            if (kIsWeb) {
              return LearnScreen(
                initialTopic: topic,
                section: section,
                programmingSubject: programming,
              );
            }
            return ModelGate(
              child: LearnScreen(
                initialTopic: topic,
                section: section,
                programmingSubject: programming,
              ),
            );
          }),
          GoRoute(
            path: '/home',
            redirect: (_, __) => '/',
          ),
          GoRoute(
            path: '/chat',
            redirect: (_, state) {
              final q = state.uri.query;
              return q.isEmpty ? '/' : '/?$q';
            },
          ),
          GoRoute(path: '/learn', builder: (_, __) => const SubjectsScreen()),
          GoRoute(
            path: '/teacher/materials',
            builder: (_, __) => const LessonMaterialsScreen(),
          ),
          GoRoute(
            path: '/learn/subject/:id',
            builder: (_, state) => UnitsScreen(
              subjectId: state.pathParameters['id'] ?? '',
            ),
          ),
          GoRoute(
            path: '/learn/subject/:id/lesson/:unit/:lesson',
            builder: (_, state) => LessonScreen(
              subjectId: state.pathParameters['id'] ?? '',
              unitIndex: int.tryParse(state.pathParameters['unit'] ?? '0') ?? 0,
              lessonIndex: int.tryParse(state.pathParameters['lesson'] ?? '0') ?? 0,
            ),
          ),
          GoRoute(
            path: '/path/:topic',
            builder: (_, state) => PathDetailScreen(
              topic: Uri.decodeComponent(state.pathParameters['topic'] ?? ''),
            ),
          ),
          GoRoute(path: '/practice', builder: (_, __) => const PracticeScreen()),
          GoRoute(path: '/create', builder: (_, __) => const CreateScreen()),
          GoRoute(path: '/weblab', builder: (_, __) => const WebDevLabScreen()),
          GoRoute(path: '/applab', builder: (_, __) => const AppDevLabScreen()),
          GoRoute(
            path: '/appchat',
            builder: (_, __) => const AppChatBuilderScreen(),
          ),
          GoRoute(
            path: '/sitebuilder',
            redirect: (_, __) => '/sitechat',
          ),
          GoRoute(path: '/sitechat', builder: (_, __) => const SiteChatBuilderScreen()),
          GoRoute(path: '/pythonlab', builder: (_, __) => const PythonLabScreen()),
          GoRoute(path: '/website', builder: (_, __) => const WebsiteBuilderScreen()),
          GoRoute(path: '/projects', builder: (_, __) => const ProjectsScreen()),
          GoRoute(path: '/achievements', builder: (_, __) => const AchievementsScreen()),
          GoRoute(path: '/certificates', builder: (_, __) => const CertificatesScreen()),
          GoRoute(path: '/teacher', builder: (_, __) => const TeacherDashboardScreen()),
          GoRoute(
            path: '/teacher/:id',
            builder: (_, state) => TeacherStudentDetailScreen(
              studentId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
            ),
          ),
          GoRoute(path: '/admin', builder: (_, __) => const AdminScreen()),
          GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
        ],
      ),
    ],
  );
});
