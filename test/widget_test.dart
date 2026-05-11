import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduler/auth/sign_in_screen.dart';

void main() {
  testWidgets('Sign-in screen renders', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: SignInScreen()),
    );
    expect(find.text('Group Schedule'), findsOneWidget);
  });
}
