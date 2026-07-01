import 'package:flutter_test/flutter_test.dart';
import 'package:sublens/main.dart';

void main() {
  testWidgets('Sublens App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const SublensApp());
    // Verify app renders without errors
    expect(find.byType(SublensApp), findsOneWidget);
  });
}
