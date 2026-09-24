/// Time-of-day salutation for the Home greeting, in English (the key that
/// `tr` looks up). Morning until noon, afternoon until 5 pm, then evening.
String timeOfDaySalutation(DateTime now) {
  if (now.hour < 12) return 'Good morning';
  if (now.hour < 17) return 'Good afternoon';
  return 'Good evening';
}

/// The learner's given ("Christian") name: the first word of the saved
/// profile name, so "Emmanuel Mujuzi" greets as "Emmanuel". Null when there
/// is no name to use (guest, or a blank profile).
String? givenName(String? fullName) {
  final trimmed = fullName?.trim() ?? '';
  if (trimmed.isEmpty) return null;
  return trimmed.split(RegExp(r'\s+')).first;
}
