import 'package:flutter_test/flutter_test.dart';
import 'package:pariksha_example/main.dart';

void main() {
  testWidgets('the example app starts', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    expect(find.text('Pariksha kit: native check'), findsOneWidget);
  });
}
