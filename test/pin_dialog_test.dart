import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_connect_africa/features/teacher/teacher_pin_screen.dart';

void main() {
  // A wrong PIN rebuilds the screen behind the dialog while it is still
  // closing. That used to hit the dialog's already-disposed controller and
  // crash instead of saying the PIN was wrong.
  testWidgets('a wrong PIN says so instead of crashing', (tester) async {
    String? entered;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                entered = await askTeacherPin(context, title: 'PIN');
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('That PIN is not right.')),
                );
              },
              child: const Text('Sign in'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '9999');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(entered, '9999');
    expect(find.text('That PIN is not right.'), findsOneWidget);
  });
}
