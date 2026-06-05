// Smoke test: l'app si avvia e mostra la shell con le 4 voci di navigazione.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transito/api/models.dart';
import 'package:transito/main.dart';
import 'package:transito/theme/app_theme.dart';
import 'package:transito/widgets/line_pill.dart';

void main() {
  testWidgets('App si avvia con la bottom navigation', (tester) async {
    await tester.pumpWidget(const TransitoApp());
    await tester.pump();

    expect(find.text('Mappa'), findsOneWidget);
    expect(find.text('Preferiti'), findsOneWidget);
    expect(find.text('Avvisi'), findsOneWidget);
  });

  testWidgets('LinePill mostra numero e icona corretta per modalità', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(
        body: Column(
          children: [
            LinePill(number: '10', mode: LineMode.tram),
            LinePill(number: '55', mode: LineMode.bus),
          ],
        ),
      ),
    ));
    expect(find.text('10'), findsOneWidget);
    expect(find.text('55'), findsOneWidget);
    expect(find.byIcon(Icons.tram), findsOneWidget);
    expect(find.byIcon(Icons.directions_bus), findsOneWidget);
  });

  test('modeForLine riconosce i tram torinesi noti', () {
    expect(modeForLine('4'), LineMode.tram);
    expect(modeForLine('55'), LineMode.bus);
    expect(modeForLine(null), LineMode.bus);
  });
}
