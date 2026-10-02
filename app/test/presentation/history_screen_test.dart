import 'package:agrispectra/core/providers.dart';
import 'package:agrispectra/core/theme/app_theme.dart';
import 'package:agrispectra/database/app_database.dart';
import 'package:agrispectra/presentation/screens/crop_selection_screen.dart';
import 'package:agrispectra/presentation/screens/history_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Regression coverage for the "Start a scan" empty-state button added in
/// the capture/result/history UX review — nothing exercised HistoryScreen
/// through a real router before, so a button that renders correctly but
/// silently fails to navigate (an easy mistake with onPressed closures)
/// would have gone unnoticed.
void main() {
  late AppDatabase appDb;

  setUp(() async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(
      'file:history_screen_${DateTime.now().microsecondsSinceEpoch}?mode=memory&cache=shared',
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await AppDatabase.createSchemaForTesting(db);
    appDb = AppDatabase.forTesting(db);
    addTearDown(db.close);
  });

  Widget harness() {
    final router = GoRouter(
      initialLocation: '/history',
      routes: [
        GoRoute(path: '/history', builder: (context, state) => const HistoryScreen()),
        GoRoute(path: '/scan/crop', builder: (context, state) => const CropSelectionScreen()),
      ],
    );
    return ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(appDb)],
      child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    );
  }

  // sqflite_common_ffi's queries complete via real OS-level async I/O, not
  // just Timers/microtasks — `pumpAndSettle()` alone runs under Flutter's
  // fake test clock and never observes that real completion, so the
  // "loading" spinner never clears no matter how many times it's pumped.
  // `runAsync` steps outside the fake clock to let the real Future actually
  // resolve, then a normal pump picks up the rebuild.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }

  testWidgets('empty history shows a "No scans yet" message, not a blank screen', (tester) async {
    await tester.pumpWidget(harness());
    await settle(tester);

    expect(find.text('No scans yet.'), findsOneWidget);
    expect(find.text('Start a scan'), findsOneWidget);
  });

  testWidgets('tapping "Start a scan" on the empty state navigates to crop selection', (tester) async {
    await tester.pumpWidget(harness());
    await settle(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Start a scan'));
    await tester.pumpAndSettle();

    expect(find.byType(CropSelectionScreen), findsOneWidget);
    expect(find.text('Select Crop'), findsOneWidget);
  });

  testWidgets('a crop-filtered empty state names the filtered crop', (tester) async {
    await tester.pumpWidget(harness());
    await settle(tester);

    await tester.tap(find.text('Barley'));
    await settle(tester);

    expect(find.text('No Barley scans yet.'), findsOneWidget);
  });
}
