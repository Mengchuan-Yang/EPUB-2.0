// Basic Flutter widget test for EpubReaderApp.
import 'package:flutter_test/flutter_test.dart';
import 'package:epub_reader/main.dart';

void main() {
  testWidgets('Bookshelf smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const EpubReaderApp());

    // Verify that our app displays the bookshelf title
    expect(find.text('我的书架'), findsOneWidget);
  });
}
