import 'package:flutter_test/flutter_test.dart';
import 'package:ai_connect_africa/features/learn/home_greeting.dart';

void main() {
  test('salutation follows the time of day', () {
    expect(timeOfDaySalutation(DateTime(2026, 9, 24, 7)), 'Good morning');
    expect(timeOfDaySalutation(DateTime(2026, 9, 24, 11, 59)), 'Good morning');
    expect(timeOfDaySalutation(DateTime(2026, 9, 24, 12)), 'Good afternoon');
    expect(timeOfDaySalutation(DateTime(2026, 9, 24, 16, 59)), 'Good afternoon');
    expect(timeOfDaySalutation(DateTime(2026, 9, 24, 17)), 'Good evening');
    expect(timeOfDaySalutation(DateTime(2026, 9, 24, 0, 30)), 'Good morning');
  });

  test('given name is the first word of the profile name', () {
    expect(givenName('Emmanuel Mujuzi'), 'Emmanuel');
    expect(givenName('  Emmanuel  '), 'Emmanuel');
    expect(givenName(''), isNull);
    expect(givenName(null), isNull);
  });
}
