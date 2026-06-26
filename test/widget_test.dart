import 'package:flutter_test/flutter_test.dart';

import 'package:settle_after_descent/main.dart';

void main() {
  testWidgets('SettleAfterDescent renders the trip list', (tester) async {
    await tester.pumpWidget(const SettleAfterDescent());

    expect(find.text('下山算账'), findsOneWidget);
    expect(find.text('2026端午节雅拉正穿'), findsOneWidget);
  });
}
