import 'package:sqflite/sqflite.dart';

import '../../domain/entities/spectral_measurement.dart';
import '../app_database.dart';

class SpectralMeasurementDao {
  SpectralMeasurementDao(this._db);
  final Database _db;

  Future<void> insert(SpectralMeasurement m) async {
    await _db.insert(
      'spectral_measurements',
      {
        'scan_id': m.scanId,
        'device_id': m.deviceId,
        'timestamp': m.timestamp.toIso8601String(),
        'wavelengths': encodeJson(m.wavelengthsNm),
        'raw_values': encodeJson(m.rawValues),
        'dark_reference': m.darkReference == null ? null : encodeJson(m.darkReference),
        'white_reference': m.whiteReference == null ? null : encodeJson(m.whiteReference),
        'reflectance': m.reflectance == null ? null : encodeJson(m.reflectance),
        'integration_time_ms': m.integrationTimeMs,
        'temperature_c': m.temperatureC,
        'humidity_percent': m.humidityPercent,
        'is_simulated': m.isSimulated ? 1 : 0,
        'calibration_status': m.calibrationStatus,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<SpectralMeasurement?> byScanId(String scanId) async {
    final rows = await _db.query('spectral_measurements', where: 'scan_id = ?', whereArgs: [scanId]);
    if (rows.isEmpty) return null;
    final row = rows.first;

    List<double>? doubles(Object? v) =>
        v == null ? null : (decodeJsonList(v as String)).map((e) => (e as num).toDouble()).toList();

    return SpectralMeasurement(
      scanId: row['scan_id'] as String,
      deviceId: row['device_id'] as String,
      timestamp: DateTime.parse(row['timestamp'] as String),
      wavelengthsNm: doubles(row['wavelengths'])!,
      rawValues: doubles(row['raw_values'])!,
      darkReference: doubles(row['dark_reference']),
      whiteReference: doubles(row['white_reference']),
      reflectance: doubles(row['reflectance']),
      integrationTimeMs: (row['integration_time_ms'] as num).toDouble(),
      temperatureC: (row['temperature_c'] as num?)?.toDouble(),
      humidityPercent: (row['humidity_percent'] as num?)?.toDouble(),
      isSimulated: (row['is_simulated'] as int) == 1,
      calibrationStatus: row['calibration_status'] as String,
    );
  }
}
