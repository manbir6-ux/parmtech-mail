import 'package:flutter_test/flutter_test.dart';
import 'package:parm_mail/main.dart';

void main() {
  testWidgets('ParmTech Mail shell renders', (tester) async {
    await tester.pumpWidget(const ParmMailApp());
    expect(find.byType(MailHome), findsOneWidget);
  });
}
