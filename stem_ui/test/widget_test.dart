import 'package:flutter_test/flutter_test.dart';
import 'package:stem_ui/main.dart';

void main() {
  testWidgets('App loads smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const StemApp());
    expect(find.text('STUDIO MIXER'), findsOneWidget);
  });
}
