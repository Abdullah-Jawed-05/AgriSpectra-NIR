import '../../database/app_database.dart';
import '../../database/daos/scan_dao.dart';
import '../../database/daos/spectral_measurement_dao.dart';
import '../../domain/entities/scan.dart';
import '../../domain/entities/spectral_measurement.dart';
import '../../domain/value_objects/quality_class.dart';

class ScanRepository {
  ScanRepository(AppDatabase db)
      : _scanDao = ScanDao(db.db),
        _spectralDao = SpectralMeasurementDao(db.db);

  final ScanDao _scanDao;
  final SpectralMeasurementDao _spectralDao;

  Future<void> save(Scan scan, {SpectralMeasurement? spectral}) async {
    await _scanDao.insertScan(scan);
    if (spectral != null) {
      await _spectralDao.insert(spectral);
    }
  }

  Future<List<ScanSummary>> history({String? cropFilter}) =>
      _scanDao.listScans(cropFilter: cropFilter);

  Future<Scan?> byId(String scanId) => _scanDao.getScan(scanId);

  Future<SpectralMeasurement?> spectralByScanId(String scanId) => _spectralDao.byScanId(scanId);

  Future<void> delete(String scanId) => _scanDao.deleteScan(scanId);

  Future<List<SeedReviewItem>> unverifiedSeeds({int limit = 200}) => _scanDao.unverifiedSeeds(limit: limit);

  Future<int> unverifiedSeedCount() => _scanDao.unverifiedSeedCount();

  Future<void> verifySeed(String seedId, QualityClass label) => _scanDao.verifySeed(seedId, label);

  Future<List<VerifiedSeedExport>> verifiedSeeds() => _scanDao.verifiedSeeds();
}
