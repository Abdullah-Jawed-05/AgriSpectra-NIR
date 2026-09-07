import 'package:agrispectra/application/scan_orchestrator.dart';
import 'package:agrispectra/core/providers.dart';
import 'package:agrispectra/database/app_database.dart';
import 'package:agrispectra/nir/no_nir_device.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../application/scan_orchestrator_test_image.dart';

/// Regression for the "Preparing results… forever" / "Failed to load
/// history: appDatabaseProvider must be overridden" bug: nothing ran the
/// real provider graph end to end, so a nested-ProviderScope wiring
/// mistake in main.dart went unnoticed. This exercises
/// `appDatabaseProvider` -> `scanRepositoryProvider` -> a real DB write
/// and read-back through a single scope, the way the fixed main.dart does.
void main() {
  late AppDatabase appDb;

  setUp(() async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(
      'file:providers_${DateTime.now().microsecondsSinceEpoch}?mode=memory&cache=shared',
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await AppDatabase.createSchemaForTesting(db);
    appDb = AppDatabase.forTesting(db);
    addTearDown(db.close);
  });

  ProviderContainer container() {
    final c = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(appDb)],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('scanRepositoryProvider resolves when appDatabaseProvider is overridden', () {
    final repo = container().read(scanRepositoryProvider);
    expect(repo, isNotNull);
  });

  test('a scan saved through the repository provider is visible to history and the unverified count', () async {
    final c = container();
    final repo = c.read(scanRepositoryProvider);

    final scan = (await ScanOrchestrator().analyze(
      imageBytes: syntheticScanBytes(),
      crop: 'barley',
      nirDevice: NoNIRDevice(),
      cameraMetadata: const {},
    ))
        .valueOrNull!;

    await repo.save(scan);

    final history = await repo.history();
    expect(history.map((s) => s.scanId), contains(scan.scanId));

    final unverified = await c.read(unverifiedSeedCountProvider.future);
    expect(unverified, scan.numberOfSeeds);
  });
}
