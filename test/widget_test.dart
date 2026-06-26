import 'package:flutter_test/flutter_test.dart';

import 'package:money_app/main.dart';

void main() {
  testWidgets('MoneyApp renders the trip list', (tester) async {
    await tester.pumpWidget(const MoneyApp());

    expect(find.text('MoneyApp'), findsOneWidget);
    expect(find.text('2026端午节雅拉正穿'), findsOneWidget);
  });
}
