/// Versioning is deliberate and explicit everywhere a prediction, protocol,
/// or dataset could later change shape. Never bump these without updating
/// docs/ROADMAP.md — historical Scan rows keep whatever version they were
/// written with (see database/app_database.dart).
class AppVersions {
  AppVersions._();

  static const String appVersion = '0.1.0';
  static const String visionModelVersion = 'agrivision-v0-rule-engine';
  static const String nirModelVersion = 'agrinir-v0-simulated';
  static const String fusionModelVersion = 'agrifusion-v0-weighted';

  /// 0.2.0: batch taxonomy scoped to barley (good/damaged/broken/shriveled
  /// /impurities); BatchStatistics gained impurity_count + purity_ratio.
  static const String analysisVersion = '0.2.0';
  static const int nirProtocolVersion = 1;
  static const String databaseSchemaVersion = '1';
}

class ScanLimits {
  ScanLimits._();

  static const int minSeedsPerBatch = 10;
  static const int maxSeedsPerBatch = 50;

  /// Below this, the image quality gate refuses to run inference.
  static const double minAcceptableQualityScore = 0.55;
}

/// Barley is the only crop AgriSpectra currently has a labelled dataset for.
/// The enum (and the crop-selection screen that renders it) stay in place as
/// the seam for adding crops back once each has its own data + tuned model.
enum Crop { barley }

extension CropLabel on Crop {
  String get label => switch (this) {
        Crop.barley => 'Barley',
      };

  String get storageKey => name;
}
