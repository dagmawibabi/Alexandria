import 'package:alexandria/core/settings.dart';
import 'package:alexandria/core/theme.dart';
import 'package:alexandria/models/podcast.dart';
import 'package:alexandria/screens/podcasts_view.dart';
import 'package:alexandria/services/podcasts.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows page renders its grid with semantics on', (tester) async {
    final handle = tester.ensureSemantics();
    for (var i = 0; i < 7; i++) {
      Podcasts.i.subscriptions.add(Podcast(feedUrl: 'https://x.example/$i', title: 'Show $i', subscribedAt: DateTime.now()));
    }
    for (final shelf in ['all', 'recent']) {
      await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light, Settings.i), home: ShowsScreen(shelf: shelf)));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Show 3'), findsWidgets);
    }
    handle.dispose();
  });
}
