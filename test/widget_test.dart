import 'package:flutter_test/flutter_test.dart';

import 'package:posture_test/main.dart';

void main() {
  testWidgets('Posture app smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const PostureApp());

    // Verify that the app title is displayed.
    expect(find.text('Posture Monitor'), findsOneWidget);

    // Verify that the 'Recalibrate' button is present.
    expect(find.text('Recalibrate'), findsOneWidget);

    // Verify that the 'Simulate Bad Posture' button is present.
    expect(find.text('Simulate Bad Posture'), findsOneWidget);

    // You can add more specific tests based on your app's functionality
  });
}
