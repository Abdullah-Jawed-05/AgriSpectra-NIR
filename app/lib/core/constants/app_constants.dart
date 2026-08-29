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
  static const String analysisVersion = '0.1.0';
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

enum Crop { wheat, rice, cotton, maize, other }

extension CropLabel on Crop {
  String get label => switch (this) {
        Crop.wheat => 'Wheat',
        Crop.rice => 'Rice',
        Crop.cotton => 'Cotton',
        Crop.maize => 'Maize',
        Crop.other => 'Other',
      };

  String get storageKey => name;
}
