import 'package:flutter_test/flutter_test.dart';
import 'package:grow_calculator/main.dart';

void main() {
  testWidgets('App loads smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const TradeTrackerApp());
    expect(find.text('Intraday Calc'), findsOneWidget);
  });
}
