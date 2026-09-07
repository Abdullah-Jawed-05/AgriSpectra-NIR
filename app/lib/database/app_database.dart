import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

/// Owns the single sqlite connection and the schema (§25 of the build
/// spec). Schema changes must go through [_migrations] — never alter a
/// released version's table shape in place.
class AppDatabase {
  AppDatabase._(this.db);

  final Database db;

  static AppDatabase? _instance;

  static Future<AppDatabase> open() async {
    if (_instance != null) return _instance!;

    if (kIsWeb) {
      databaseFactory = databaseFactoryFfiWeb;
    }
    final factory = databaseFactory;

    final String path;
    if (kIsWeb) {
      path = 'agrispectra.db';
    } else {
      final dir = await getApplicationDocumentsDirectory();
      path = p.join(dir.path, 'agrispectra.db');
    }

    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onCreate: (db, version) async {
          for (final statement in _createStatements) {
            await db.execute(statement);
          }
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          for (final migration in _migrations.entries) {
            if (migration.key > oldVersion) {
              for (final statement in migration.value) {
                await db.execute(statement);
              }
            }
          }
        },
      ),
    );

    _instance = AppDatabase._(db);
    return _instance!;
  }

  static const int schemaVersion = 2;

  /// Runs the real create statements against an arbitrary already-open
  /// [Database] — e.g. an in-memory `sqflite_common_ffi` database in a
  /// test — so DAO tests exercise the actual production schema instead of
  /// a hand-duplicated copy that could silently drift from it.
  @visibleForTesting
  static Future<void> createSchemaForTesting(Database db) async {
    for (final statement in _createStatements) {
      await db.execute(statement);
    }
  }

  /// Wraps an already-open [Database] as an [AppDatabase] so a test can put
  /// it behind `appDatabaseProvider` and exercise the real repository /
  /// provider graph.
  @visibleForTesting
  factory AppDatabase.forTesting(Database db) = AppDatabase._;

  /// The additive migration steps, keyed by the version they upgrade *to*
  /// — exposed so a test can build a v1 database, apply them, and check an
  /// existing install would survive the upgrade (§25 "never alter a
  /// released version's table shape in place").
  @visibleForTesting
  static Map<int, List<String>> get migrationsForTesting => _migrations;

  static const List<String> _createStatements = [
    '''
    CREATE TABLE scans (
      scan_id TEXT PRIMARY KEY,
      timestamp TEXT NOT NULL,
      crop TEXT NOT NULL,
      cultivar TEXT,
      location TEXT,
      camera_metadata TEXT NOT NULL,
      image_quality TEXT NOT NULL,
      number_of_seeds INTEGER NOT NULL,
      batch_score REAL NOT NULL,
      confidence REAL NOT NULL,
      vision_model_version TEXT NOT NULL,
      analysis_version TEXT NOT NULL,
      nir_available INTEGER NOT NULL,
      nir_device_id TEXT,
      batch_statistics TEXT NOT NULL,
      fusion_result TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE seed_results (
      seed_id TEXT PRIMARY KEY,
      scan_id TEXT NOT NULL REFERENCES scans(scan_id) ON DELETE CASCADE,
      crop_png BLOB NOT NULL,
      segmentation TEXT NOT NULL,
      visual_features TEXT NOT NULL,
      prediction TEXT NOT NULL,
      confidence REAL NOT NULL,
      anomalies TEXT NOT NULL,
      verified_label TEXT,
      verified_at TEXT
    )
    ''',
    'CREATE INDEX idx_seed_results_scan_id ON seed_results(scan_id)',
    'CREATE INDEX idx_seed_results_verified_label ON seed_results(verified_label)',
    '''
    CREATE TABLE spectral_measurements (
      scan_id TEXT PRIMARY KEY REFERENCES scans(scan_id) ON DELETE CASCADE,
      device_id TEXT NOT NULL,
      timestamp TEXT NOT NULL,
      wavelengths TEXT NOT NULL,
      raw_values TEXT NOT NULL,
      dark_reference TEXT,
      white_reference TEXT,
      reflectance TEXT,
      integration_time_ms REAL NOT NULL,
      temperature_c REAL,
      humidity_percent REAL,
      is_simulated INTEGER NOT NULL,
      calibration_status TEXT NOT NULL
    )
    ''',
  ];

  /// Additive-only migrations, keyed by the version they upgrade *to*.
  static const Map<int, List<String>> _migrations = {
    2: [
      'ALTER TABLE seed_results ADD COLUMN verified_label TEXT',
      'ALTER TABLE seed_results ADD COLUMN verified_at TEXT',
      'CREATE INDEX idx_seed_results_verified_label ON seed_results(verified_label)',
    ],
  };
}

String encodeJson(Object? value) => jsonEncode(value);
Map<String, Object?> decodeJsonMap(String value) =>
    (jsonDecode(value) as Map).cast<String, Object?>();
List<Object?> decodeJsonList(String value) => jsonDecode(value) as List<Object?>;
