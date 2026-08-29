import 'dart:math' as math;

import '../core/constants/app_constants.dart';
import '../domain/entities/quality_prediction.dart';
import '../domain/entities/seed_features.dart';
import '../domain/value_objects/quality_class.dart';

/// Model V0 (§43): a rule engine over the extracted [SeedFeatures], not a
/// trained model. This exists to prove the full pipeline works end-to-end
/// honestly, before any labeled training data exists — see
/// docs/ML_PIPELINE.md for the plan to replace this with a trained
/// classifier (Model V1) once a real dataset is collected.
///
/// Thresholds below are engineering judgment calibrated against a handful
/// of reference seeds, not a statistically validated cutoff. They are
/// deliberately named constants so they're easy to revisit once V1 data
/// exists.
class RuleBasedClassifier {
  const RuleBasedClassifier();

  static const double _highDamageDarkRatio = 0.18;
  static const double _highCrackRatio = 0.35;
  static const double _highHoleRatio = 0.02;
  static const double _highDiscoloration = 0.3;
  static const double _lowCircularity = 0.55;
  static const double _highEccentricity = 0.85;

  QualityPrediction classify(SeedFeatures features) {
    final evidence = <EvidenceFactor>[];
    final anomalies = <String>[];
    double penalty = 0;

    // Damage / dark regions.
    if (features.damage.darkRegionRatio > _highDamageDarkRatio) {
      final strength = ((features.damage.darkRegionRatio - _highDamageDarkRatio) * 2).clamp(0.0, 1.0);
      penalty += 22 * strength;
      evidence.add(EvidenceFactor(
        description: 'Notable dark/discolored surface regions',
        supportsGoodQuality: false,
        weight: strength,
      ));
      anomalies.add('dark_surface_regions');
    } else {
      evidence.add(const EvidenceFactor(
        description: 'Low visible dark-region ratio',
        supportsGoodQuality: true,
        weight: 0.3,
      ));
    }

    // Crack-like edge density.
    if (features.damage.crackLikeEdgeRatio > _highCrackRatio) {
      final strength =
          ((features.damage.crackLikeEdgeRatio - _highCrackRatio) * 1.5).clamp(0.0, 1.0);
      penalty += 18 * strength;
      evidence.add(EvidenceFactor(
        description: 'High surface irregularity (possible cracking)',
        supportsGoodQuality: false,
        weight: strength,
      ));
      anomalies.add('possible_surface_cracking');
    } else {
      evidence.add(const EvidenceFactor(
        description: 'Smooth, low-irregularity surface',
        supportsGoodQuality: true,
        weight: 0.25,
      ));
    }

    // Holes (possible insect damage).
    if (features.damage.holeRatio > _highHoleRatio) {
      final strength = (features.damage.holeRatio / (_highHoleRatio * 4)).clamp(0.0, 1.0);
      penalty += 20 * strength;
      evidence.add(EvidenceFactor(
        description: 'Small enclosed voids detected (possible insect damage)',
        supportsGoodQuality: false,
        weight: strength,
      ));
      anomalies.add('possible_insect_damage');
    }

    // Discoloration.
    if (features.color.discolorationRatio > _highDiscoloration) {
      final strength =
          ((features.color.discolorationRatio - _highDiscoloration) * 1.4).clamp(0.0, 1.0);
      penalty += 16 * strength;
      evidence.add(EvidenceFactor(
        description: 'Uneven color distribution',
        supportsGoodQuality: false,
        weight: strength,
      ));
      anomalies.add('color_inconsistency');
    } else {
      evidence.add(const EvidenceFactor(
        description: 'Normal color distribution',
        supportsGoodQuality: true,
        weight: 0.3,
      ));
    }

    // Shape — low circularity or high eccentricity suggests shriveling or
    // malformation.
    if (features.geometry.circularity < _lowCircularity ||
        features.geometry.eccentricity > _highEccentricity) {
      final strength = math.max(
        (_lowCircularity - features.geometry.circularity).clamp(0.0, 1.0),
        (features.geometry.eccentricity - _highEccentricity).clamp(0.0, 1.0) * 2,
      );
      penalty += 14 * strength;
      evidence.add(EvidenceFactor(
        description: 'Irregular or elongated shape',
        supportsGoodQuality: false,
        weight: strength,
      ));
      anomalies.add('shape_irregularity');
    } else {
      evidence.add(const EvidenceFactor(
        description: 'Uniform, expected shape',
        supportsGoodQuality: true,
        weight: 0.15,
      ));
    }

    final score = (100 - penalty).clamp(0.0, 100.0);

    final qualityClass = _classify(features, anomalies);

    // Confidence reflects how far the score is from the decision boundary
    // and how much evidence was collected, not a calibrated probability —
    // a rule engine has no real notion of calibrated uncertainty (§20).
    final decisiveness = (penalty - 25).abs() / 25;
    final confidence = (0.55 + 0.35 * decisiveness.clamp(0.0, 1.0)).clamp(0.0, 0.95);

    return QualityPrediction(
      qualityClass: qualityClass,
      score: score,
      confidence: confidence,
      evidence: evidence,
      anomalies: anomalies,
      modelVersion: AppVersions.visionModelVersion,
    );
  }

  // Deliberately does not return QualityClass.broken or .shellFree: this
  // rule engine has no real barley reference photos to derive a heuristic
  // for "physically fragmented" or "hull missing" against, and guessing
  // thresholds for those without any visual reference would be exactly
  // the kind of fabricated-looking-precise behavior this project avoids
  // elsewhere (§66 of the build spec). Model V1, trained on the labeled
  // dataset that includes real examples of both, is what should actually
  // learn to detect them — see docs/ML_PIPELINE.md.
  QualityClass _classify(SeedFeatures f, List<String> anomalies) {
    if (anomalies.contains('possible_insect_damage')) return QualityClass.insectDamaged;
    if (f.damage.darkRegionRatio > _highDamageDarkRatio * 1.6) return QualityClass.moldSuspect;
    if (anomalies.contains('color_inconsistency')) return QualityClass.discolored;
    if (anomalies.contains('shape_irregularity')) return QualityClass.shriveled;
    if (anomalies.contains('possible_surface_cracking') ||
        anomalies.contains('dark_surface_regions')) {
      return QualityClass.damaged;
    }
    return QualityClass.good;
  }
}
