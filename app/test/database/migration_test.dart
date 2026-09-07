import 'dart:typed_data';

import 'package:agrispectra/database/app_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The v1 `seed_results` shape — before `verified_label` / `verified_at`
/// were added. If an existing install can't survive the v1→v2 upgrade the
/// app won't open for anyone who already used it.
const _v1SeedResults = '''
  CREATE TABLE seed_results (
    seed_id TEXT PRIMARY KEY,
    scan_id TEXT NOT NULL,
    crop_png BLOB NOT NULL,
    segmentation TEXT NOT NULL,
    visual_features TEXT NOT NULL,
    prediction TEXT NOT NULL,
    confidence REAL NOT NULL,
    anomalies TEXT NOT NULL
  )
''';

void main() {
  test('v1 -> v2 migration adds the verification columns and keeps existing rows', () async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(
      'file:migration_${DateTime.now().microsecondsSinceEpoch}?mode=memory&cache=shared',
      options: OpenDatabaseOptions(singleInstance: false),
    );
    addTearDown(db.close);

    // Stand up a v1 database with a row already in it.
    await db.execute(_v1SeedResults);
    await db.insert('seed_results', {
      'seed_id': 'legacy_1',
      'scan_id': 'scan_1',
      'crop_png': Uint8List.fromList([1, 2, 3]),
      'segmentation': '{}',
      'visual_features': '{}',
      'prediction': '{}',
      'confidence': 0.5,
      'anomalies': '[]',
    });

    // Apply every migration keyed above the starting version.
    for (final entry in AppDatabase.migrationsForTesting.entries) {
      if (entry.key > 1) {
        for (final statement in entry.value) {
          await db.execute(statement);
        }
      }
    }

    final cols = (await db.rawQuery('PRAGMA table_info(seed_results)'))
        .map((r) => r['name'] as String)
        .toSet();
    expect(cols, containsAll(['verified_label', 'verified_at']));

    final rows = await db.query('seed_results', where: 'seed_id = ?', whereArgs: ['legacy_1']);
    expect(rows, hasLength(1));
    expect(rows.single['verified_label'], isNull);
    expect(rows.single['confidence'], 0.5);

    // The new columns are writable.
    await db.update('seed_results', {'verified_label': 'GOOD'}, where: 'seed_id = ?', whereArgs: ['legacy_1']);
    final updated = await db.query('seed_results', where: 'seed_id = ?', whereArgs: ['legacy_1']);
    expect(updated.single['verified_label'], 'GOOD');
  });
}
