import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:count_board_kit/main.dart';

void main() {
  testWidgets('starter board increments a counter', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const CountBoardApp(showAds: false));
    await tester.pumpAndSettle();

    expect(find.text('Count Board Kit'), findsOneWidget);
    expect(find.text('Stock check'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);

    await tester.tap(find.byTooltip('Add one').first);
    await tester.pumpAndSettle();

    expect(find.text('13'), findsOneWidget);
  });
}
