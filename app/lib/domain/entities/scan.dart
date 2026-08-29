import 'batch_statistics.dart';
import 'fusion_result.dart';
import 'image_quality_report.dart';
import 'seed_result.dart';

/// A single completed scan (§25 `Scan` table) — one batch of seeds
/// captured, analyzed, and scored together.
class Scan {
  final String scanId;
  final DateTime timestamp;
  final String crop;
  final String? cultivar;
  final String? location;
  final Map<String, Object?> cameraMetadata;

  final ImageQualityReport imageQuality;
  final int numberOfSeeds;
  final double batchScore;
  final double confidence;

  final String visionModelVersion;
  final String analysisVersion;

  final bool nirAvailable;
  final String? nirDeviceId;

  final BatchStatistics batchStatistics;
  final FusionResult fusionResult;
  final List<SeedResult> results;

  const Scan({
    required this.scanId,
    required this.timestamp,
    required this.crop,
    this.cultivar,
    this.location,
    required this.cameraMetadata,
    required this.imageQuality,
    required this.numberOfSeeds,
    required this.batchScore,
    required this.confidence,
    required this.visionModelVersion,
    required this.analysisVersion,
    required this.nirAvailable,
    this.nirDeviceId,
    required this.batchStatistics,
    required this.fusionResult,
    required this.results,
  });
}
