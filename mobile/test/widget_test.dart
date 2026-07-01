import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/main.dart';

void main() {
  testWidgets('Sublens App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const SublensApp());

    // Verify that our Get Started button exists.
    expect(find.text('Get Started'), findsOneWidget);
  });
}
