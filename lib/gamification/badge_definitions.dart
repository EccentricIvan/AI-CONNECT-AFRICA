import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';

class BadgeDef {
  const BadgeDef({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.color,
    required this.points,
  });

  final String id;
  final String name;
  final String description;
  final IconData icon;
  final Color color;
  final int points;
}

const allBadges = <BadgeDef>[
  BadgeDef(
    id: 'first_lesson',
    name: 'First Step',
    description: 'Completed your very first lesson',
    icon: Icons.play_circle,
    color: AppColors.learnColor,
    points: 50,
  ),
  BadgeDef(
    id: 'path_master',
    name: 'Path Master',
    description: 'Completed a full 12-lesson learning path',
    icon: Icons.route,
    color: AppColors.teachColor,
    points: 200,
  ),
  BadgeDef(
    id: 'practice_starter',
    name: 'Quiz Taker',
    description: 'Attempted your first practice exercise',
    icon: Icons.quiz,
    color: AppColors.practiceColor,
    points: 30,
  ),
  BadgeDef(
    id: 'sharp_mind',
    name: 'Sharp Mind',
    description: 'Got 5 practice questions correct in total',
    icon: Icons.psychology,
    color: AppColors.secondary,
    points: 100,
  ),
  BadgeDef(
    id: 'scenario_solver',
    name: 'Scenario Solver',
    description: 'Completed 5 real-world Apply scenarios',
    icon: Icons.explore,
    color: AppColors.createColor,
    points: 100,
  ),
  BadgeDef(
    id: 'creator',
    name: 'Creator',
    description: 'Saved your first learning project',
    icon: Icons.lightbulb,
    color: AppColors.createColor,
    points: 80,
  ),
  BadgeDef(
    id: 'consistent_learner',
    name: 'Consistent Learner',
    description: 'Learned for 7 days in a row',
    icon: Icons.local_fire_department,
    color: Colors.orange,
    points: 150,
  ),
  BadgeDef(
    id: 'polymath',
    name: 'Polymath',
    description: 'Started learning paths in 3 different topics',
    icon: Icons.auto_awesome,
    color: AppColors.primary,
    points: 120,
  ),
  BadgeDef(
    id: 'century',
    name: 'Century',
    description: 'Earned 100 total points',
    icon: Icons.stars,
    color: Colors.amber,
    points: 0,
  ),
];

BadgeDef? badgeById(String id) {
  try {
    return allBadges.firstWhere((b) => b.id == id);
  } catch (_) {
    return null;
  }
}
