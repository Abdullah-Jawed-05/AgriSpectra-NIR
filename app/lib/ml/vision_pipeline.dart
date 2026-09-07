import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../domain/entities/batch_statistics.dart';
import '../domain/entities/image_quality_report.dart';
import '../domain/entities/processed_seed.dart';
import 'batch_engine.dart';
import 'feature_extractor.dart';
import 'image_quality_gate.dart';
import 'impurity_detector.dart';
import 'rule_classifier.dart';
import 'seed_finder.dart';

/// Everything the camera-only vision pipeline produces from one captured
/// image: quality gate → detect/segment → extract → classify → aggregate
/// (§5 of the architecture doc). [errorMessage] is set, and [processedSeeds]
/// /[batchStatistics] are null, whenever the pipeline stopped early (poor
/// image quality, no seeds found).
class VisionPipelineResult {
  final ImageQualityReport quality;
  final int seedsDetected;
  final int seedsRejected;
  final List<ProcessedSeed>? processedSeeds;
  final BatchStatistics? batchStatistics;
  final String? errorMessage;

  const VisionPipelineResult({
    required this.quality,
    required this.seedsDetected,
    required this.seedsRejected,
    this.processedSeeds,
    this.batchStatistics,
    this.errorMessage,
  });
}

/// Runs the full CPU-bound vision pipeline for one captured image. This is
/// a plain top-level function — deliberately not a method on
/// [ScanOrchestrator] — so it can be handed to `compute()` and executed on
/// a background isolate.
///
/// Why this matters: without this, the entire pipeline (quality gate,
/// detection/segmentation, and per-seed feature extraction/classification
/// for up to 50 seeds) ran synchronously on the UI isolate. Dart is
/// single-threaded per isolate, so Flutter cannot repaint — not even the
/// "Analyzing" screen's own loading spinner — while that runs. On a real
/// (especially debug-build) device that reads as the app hanging, not
/// just being slow. Running it on a separate isolate keeps the UI
/// responsive for however long the actual computation takes.
VisionPipelineResult runVisionPipeline(Uint8List imageBytes) {
  const qualityGate = ImageQualityGate();
  final seedFinder = ClassicalCVSeedFinder();
  const featureExtractor = FeatureExtractor();
  const classifier = RuleBasedClassifier();
  const impurityDetector = ImpurityDetector();
  const batchEngine = BatchEngine();

  final image = img.decodeImage(imageBytes);
  if (image == null) {
    return const VisionPipelineResult(
      quality: ImageQualityReport(
        usable: false,
        qualityScore: 0,
        blurScore: 0,
        exposureScore: 0,
        glareScore: 0,
        backgroundScore: 0,
        textureScore: 0,
        warnings: ['Could not read the captured image.'],
      ),
      seedsDetected: 0,
      seedsRejected: 0,
      errorMessage: 'Could not read the captured image. Please try again.',
    );
  }

  final quality = qualityGate.evaluate(image);
  if (!quality.usable) {
    return VisionPipelineResult(
      quality: quality,
      seedsDetected: 0,
      seedsRejected: 0,
      errorMessage: quality.warnings.isNotEmpty
          ? quality.warnings.join(' ')
          : 'Image quality is too low for reliable analysis.',
    );
  }

  final segmented = seedFinder.find(image);
  if (segmented.isEmpty) {
    return VisionPipelineResult(
      quality: quality,
      seedsDetected: 0,
      seedsRejected: seedFinder.lastRejectedCandidates,
      errorMessage: 'No seeds detected. Make sure seeds are spread out, in focus, and contrast '
          'clearly against the background, then try again.',
    );
  }

  final classified = <ProcessedSeed>[];
  for (final seed in segmented) {
    final features = featureExtractor.extract(seed);
    final prediction = classifier.classify(features);
    classified.add(ProcessedSeed(
      seedId: seed.seedId,
      cropPng: img.encodePng(seed.crop),
      mask: seed.mask,
      maskWidth: seed.crop.width,
      maskHeight: seed.crop.height,
      boundingBox: seed.boundingBox,
      contour: seed.contour,
      center: seed.center,
      orientationRadians: seed.orientationRadians,
      features: features,
      prediction: prediction,
    ));
  }

  // Foreign-matter screening is a batch-relative call, so it runs once over
  // the whole set of classified detections rather than per seed.
  final processed = impurityDetector.flag(classified);

  final batchStats = batchEngine.aggregate(
    seedsDetected: segmented.length,
    accepted: processed,
    seedsRejected: seedFinder.lastRejectedCandidates,
  );

  return VisionPipelineResult(
    quality: quality,
    seedsDetected: segmented.length,
    seedsRejected: seedFinder.lastRejectedCandidates,
    processedSeeds: processed,
    batchStatistics: batchStats,
  );
}
