// Smoke test: the app theme builds and a MaterialApp using it renders
// without throwing. Full app startup (AppDatabase.open, camera, BLE)
// needs platform channels/FFI that aren't available under `flutter test`
// on this host — see test/README or docs/ARCHITECTURE.md §10. Screen-level
// widget tests belong in test/presentation/ once each screen's providers
// can be overridden with fakes (§57 of the build spec).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agrispectra/core/theme/app_theme.dart';

void main() {
  testWidgets('AppTheme renders a basic scaffold', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: Center(child: Text('AgriSpectra'))),
    ));

    expect(find.text('AgriSpectra'), findsOneWidget);
  });
}
