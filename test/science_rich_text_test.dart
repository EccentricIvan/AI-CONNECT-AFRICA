import 'package:ai_connect_africa/shared/widgets/science_rich_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      "a fenced code block's identifiers are not mangled by the chemistry "
      'subscript pass meant for prose', (tester) async {
    // Single-letter, capitalized identifiers — V and N are both in the
    // element-symbol list applyLatexChemistryUnicode matches on, so this is
    // exactly the shape that pass would (wrongly) convert outside a guard.
    const code = '```python\nV_0 = 5\nN_1 = 2\n```';

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ScienceRichText(text: code)),
      ),
    );
    await tester.pump();

    expect(find.textContaining('V_0'), findsOneWidget,
        reason: 'the code must still be found unmangled — a failure to '
            'match here would make the negative assertion below meaningless');
    expect(find.textContaining('V₀'), findsNothing);
  });
}
