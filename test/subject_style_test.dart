import 'package:flutter_test/flutter_test.dart';
import 'package:ai_connect_africa/curriculum/subject_style.dart';

void main() {
  String icon(String name) => subjectStyleFor(name).icon;
  String color(String name) => subjectStyleFor(name).color;

  test('a school subject gets its own subject\'s look', () {
    expect(icon('Mathematics'), 'calculate');
    expect(icon('S.4 Maths'), 'calculate');
    expect(icon('Chemistry'), 'science_outlined');
    expect(icon('Senior 4 Chemistry'), 'science_outlined');
    expect(icon('Physics'), 'science');
    expect(icon('Biology'), 'biotech');
    expect(icon('Kiswahili'), 'translate');
    expect(icon('Luganda'), 'translate');
    expect(icon('CRE'), 'church');
    expect(icon('IRE'), 'church');
    expect(icon('General Paper'), 'menu_book');
    expect(icon('Commerce'), 'storefront');
    expect(icon('Accounting'), 'receipt_long');
    expect(icon('Fine Art'), 'palette');
    expect(icon('Computer Studies'), 'computer');
    expect(icon('ICT'), 'computer');
    expect(icon('Music'), 'music_note');
  });

  test('chemistry and mathematics never share a colour', () {
    expect(color('Chemistry'), isNot(color('Mathematics')));
    expect(color('Mathematics'), '#4F46E5');
  });

  test('look-alike names land on the right subject', () {
    expect(icon('Physical Education'), 'sports_soccer');
    expect(icon('Home Economics'), 'restaurant');
    expect(icon('Biochemistry'), 'biotech');
    expect(icon('Agricultural Economics'), 'grass');
    expect(icon('Literature in English'), 'auto_stories');
    expect(icon('English Language'), 'menu_book');
    expect(icon('French Language'), 'translate');
  });

  test('an unknown name gets a colour that is not maths and not taken', () {
    final first = subjectStyleFor('Beekeeping');
    expect(first.icon, 'school');
    expect(first.color, isNot('#4F46E5'));
    expect(subjectStyleFor('Beekeeping').color, first.color);
    final next = subjectStyleFor('Beekeeping', taken: [first.color]);
    expect(next.color, isNot(first.color));
  });

  test('rows stored with the old default are styled from their name', () {
    expect(shownSubjectStyle('Chemistry', 'menu_book', '#4F46E5').icon,
        'science_outlined');
    expect(shownSubjectStyle('Chemistry', 'code', '#123456'),
        (icon: 'code', color: '#123456'));
  });
}
