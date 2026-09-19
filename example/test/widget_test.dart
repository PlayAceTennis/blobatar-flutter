import 'package:blobatar_example/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('demo app renders a Blobatar', (WidgetTester tester) async {
    await tester.pumpWidget(const BlobatarDemoApp());
    expect(find.text('Blobatar demo'), findsOneWidget);
  });
}
