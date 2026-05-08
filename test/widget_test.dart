import 'package:flutter_test/flutter_test.dart';

import 'package:aiaccountant/main.dart';

void main() {
  testWidgets('renders queue first and opens capture type picker', (tester) async {
    await tester.pumpWidget(const AccountantApp());

    expect(find.text('Queue'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('ABC Traders'), findsOneWidget);

    await tester.tap(find.text('Camera'));
    await tester.pumpAndSettle();

    expect(find.text('What is this?'), findsOneWidget);
    expect(find.text('Sale'), findsWidgets);
    expect(find.text('Purchase'), findsWidgets);
  });
}
