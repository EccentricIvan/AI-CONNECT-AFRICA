import 'package:flutter/material.dart';

/// The icon and colour of a subject's card, picked from its name.
///
/// Local and instant — no model call. A school's own "Mathematics" gets the
/// maths look and its "Chemistry" the chemistry look, so two different
/// subjects never share one subject's colour by accident.
typedef SubjectStyle = ({String icon, String color});

/// Icon keys a subject may carry (bundled JSON, custom rows, sync).
const subjectIcons = <String, IconData>{
  'calculate': Icons.calculate,
  'science': Icons.science,
  'biotech': Icons.biotech,
  'science_outlined': Icons.science_outlined,
  'code': Icons.code,
  'web': Icons.web,
  'phone_android': Icons.phone_android,
  'psychology': Icons.psychology,
  'trending_up': Icons.trending_up,
  'grass': Icons.grass,
  'history_edu': Icons.history_edu,
  'public': Icons.public,
  'menu_book': Icons.menu_book,
  'account_balance': Icons.account_balance,
  'palette': Icons.palette,
  'translate': Icons.translate,
  'auto_stories': Icons.auto_stories,
  'music_note': Icons.music_note,
  'sports_soccer': Icons.sports_soccer,
  'church': Icons.church,
  'restaurant': Icons.restaurant,
  'architecture': Icons.architecture,
  'computer': Icons.computer,
  'groups': Icons.groups,
  'receipt_long': Icons.receipt_long,
  'storefront': Icons.storefront,
  'gavel': Icons.gavel,
  'health_and_safety': Icons.health_and_safety,
  'construction': Icons.construction,
  'checkroom': Icons.checkroom,
  'theater_comedy': Icons.theater_comedy,
  'eco': Icons.eco,
  'school': Icons.school,
};

IconData subjectIcon(String key) => subjectIcons[key] ?? Icons.menu_book;

/// What a custom subject was given before styles were picked from the name.
const kLegacySubjectStyle = (icon: 'menu_book', color: '#4F46E5');

/// Most specific first: "Home Economics" must hit home economics before
/// economics, "Physical Education" sports before physics, "English
/// Language" English before languages.
const _rules = <(List<String>, SubjectStyle)>[
  (['physical education', 'pe', 'sport', 'sports', 'games', 'athletics'],
      (icon: 'sports_soccer', color: '#EF4444')),
  (['home economics', 'nutrition', 'food', 'foods', 'cookery', 'catering'],
      (icon: 'restaurant', color: '#F97316')),
  (['agricultural', 'agriculture', 'farming', 'agribusiness', 'horticulture'],
      (icon: 'grass', color: '#22C55E')),
  (['biochemistry'], (icon: 'biotech', color: '#10B981')),
  (['integrated science', 'general science', 'science', 'sciences'],
      (icon: 'science', color: '#06B6D4')),
  (['mathematics', 'maths', 'math', 'algebra', 'geometry', 'arithmetic',
    'calculus', 'statistics', 'numeracy', 'hisabati'],
      (icon: 'calculate', color: '#4F46E5')),
  (['physics'], (icon: 'science', color: '#0EA5E9')),
  (['chemistry'], (icon: 'science_outlined', color: '#F59E0B')),
  (['biology', 'life science', 'botany', 'zoology'],
      (icon: 'biotech', color: '#10B981')),
  (['health', 'hygiene', 'first aid', 'nursing'],
      (icon: 'health_and_safety', color: '#E11D48')),
  (['environment', 'environmental', 'ecology', 'conservation'],
      (icon: 'eco', color: '#16A34A')),
  (['computer', 'computing', 'ict', 'it', 'information technology',
    'digital'], (icon: 'computer', color: '#3B82F6')),
  (['programming', 'coding', 'code', 'software', 'python', 'java'],
      (icon: 'code', color: '#6366F1')),
  (['web', 'website', 'websites', 'html'], (icon: 'web', color: '#0284C7')),
  (['artificial intelligence', 'ai', 'data', 'robotics'],
      (icon: 'psychology', color: '#7C3AED')),
  (['technical drawing', 'drawing', 'td', 'design and technology', 'dt'],
      (icon: 'architecture', color: '#475569')),
  (['woodwork', 'metalwork', 'building', 'carpentry', 'electrical',
    'technology', 'technical'], (icon: 'construction', color: '#A16207')),
  (['tailoring', 'fashion', 'textiles', 'needlework'],
      (icon: 'checkroom', color: '#DB2777')),
  (['accounting', 'accounts', 'bookkeeping', 'book keeping'],
      (icon: 'receipt_long', color: '#0F766E')),
  (['commerce', 'business', 'marketing', 'trade'],
      (icon: 'storefront', color: '#EA580C')),
  (['entrepreneurship', 'enterprise'], (icon: 'trending_up', color: '#D97706')),
  (['economics', 'economy'], (icon: 'account_balance', color: '#CA8A04')),
  (['music', 'mdd', 'choir', 'singing'], (icon: 'music_note', color: '#C026D3')),
  (['drama', 'theatre', 'theater', 'dance'],
      (icon: 'theater_comedy', color: '#9333EA')),
  (['fine art', 'art', 'arts', 'crafts', 'painting'],
      (icon: 'palette', color: '#EAB308')),
  (['religious', 'religion', 'cre', 'ire', 'christian', 'islamic', 'divinity',
    'bible', 'quran', 'theology'], (icon: 'church', color: '#8B5CF6')),
  (['history', 'heritage'], (icon: 'history_edu', color: '#64748B')),
  (['geography', 'atlas'], (icon: 'public', color: '#14B8A6')),
  (['social studies', 'citizenship', 'civics', 'political', 'government',
    'sociology', 'social'], (icon: 'groups', color: '#0891B2')),
  (['law', 'legal'], (icon: 'gavel', color: '#78716C')),
  (['literature', 'poetry', 'novels', 'reading'],
      (icon: 'auto_stories', color: '#BE185D')),
  (['english', 'writing', 'grammar', 'composition', 'general paper', 'gp',
    'communication', 'literacy'], (icon: 'menu_book', color: '#EC4899')),
  (['kiswahili', 'swahili', 'luganda', 'runyankole', 'lusoga', 'luo',
    'ateso', 'french', 'arabic', 'german', 'chinese', 'spanish', 'yoruba',
    'igbo', 'hausa', 'amharic', 'kinyarwanda', 'zulu', 'xhosa', 'shona',
    'language', 'languages', 'linguistics'],
      (icon: 'translate', color: '#F43F5E')),
];

/// For a name that matches nothing. Maths indigo is left out on purpose.
const _fallbackPalette = [
  '#0D9488', '#DC2626', '#2563EB', '#9333EA', '#EA580C', '#059669',
  '#DB2777', '#0891B2', '#65A30D', '#B45309', '#7C3AED', '#E11D48',
];

/// The style for a subject called [name]. [taken] are colours already on
/// other cards; a name that matches no subject avoids them where it can.
SubjectStyle subjectStyleFor(String name, {Iterable<String> taken = const []}) {
  final text = ' ${name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim()} ';
  for (final (words, style) in _rules) {
    for (final w in words) {
      if (text.contains(' $w ')) return style;
    }
  }
  final used = {for (final c in taken) c.toUpperCase()};
  final start = _stableHash(text) % _fallbackPalette.length;
  for (var i = 0; i < _fallbackPalette.length; i++) {
    final c = _fallbackPalette[(start + i) % _fallbackPalette.length];
    if (!used.contains(c)) return (icon: 'school', color: c);
  }
  return (icon: 'school', color: _fallbackPalette[start]);
}

/// The style to show for a stored subject: rows still carrying the old
/// one-size default are styled from their name, the same on every device.
SubjectStyle shownSubjectStyle(String name, String icon, String color) =>
    icon == kLegacySubjectStyle.icon &&
            color.toUpperCase() == kLegacySubjectStyle.color
        ? subjectStyleFor(name)
        : (icon: icon, color: color);

int _stableHash(String s) {
  var h = 0;
  for (final c in s.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return h;
}
