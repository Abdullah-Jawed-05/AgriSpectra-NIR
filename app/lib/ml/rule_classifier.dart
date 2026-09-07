import '../core/constants/app_constants.dart';
import '../domain/entities/quality_prediction.dart';
import '../domain/entities/seed_features.dart';
import '../domain/value_objects/quality_class.dart';

/// Model V0 (§43): a rule engine over the extracted [SeedFeatures], not a
/// trained model. It exists to prove the full pipeline works end-to-end
/// honestly, before a trained classifier (Model V1) is wired in — see
/// docs/ML_PIPELINE.md and docs/VALIDATION.md.
///
/// **Scope: V0 is a GOOD-vs-DAMAGED screen for barley, nothing more.**
/// It was re-checked (2026-09-07) against the parity-fixed features on
/// 154 hand-labelled single-seed barley photos, and the earlier rule set
/// turned out to be badly miscalibrated for this crop:
///
///  - The shape branch (`circularity < 0.55 || eccentricity > 0.85`) fired
///    on essentially every barley grain — they are naturally elongated
///    (circularity ≈ 0.17, eccentricity ≈ 0.9) — routing ~all seeds to
///    `shriveled`. Removed. Nothing in these features separates shrivelled
///    barley from sound barley (§66: don't ship a cutoff that isn't there).
///  - The discoloration branch was backwards: sound barley has a *higher*
///    hue-variance `discolorationRatio` (natural aleurone/husk colour) than
///    damaged. Removed.
///  - The hole branch carried no signal for barley (sound ≈ damaged).
///    Removed.
///
/// What's left — surface darkening and crack-like edge density — does
/// separate the two classes (balanced accuracy ≈ 0.73 on that set: ~85%
/// of sound seed kept, ~62% of damaged caught). Still a hand-tuned
/// screening heuristic, not a validated cutoff.
///
/// `broken`, `shriveled` and `impurities` are therefore never returned
/// here: `impurities` is a batch-relative call handled by
/// `ImpurityDetector` after this runs, and `broken` / `shriveled` need the
/// trained V1.
class RuleBasedClassifier {
  const RuleBasedClassifier();

  /// Fraction of the seed surface that reads as dark / off-colour. Sound
  /// barley sits near 0 (75th percentile 0.0 on the reference set);
  /// damaged seed runs much higher (median ≈ 0.17).
  static const double _highDamageDarkRatio = 0.10;

  /// Crack-like high-frequency edge density. Sound barley median ≈ 0.01,
  /// damaged ≈ 0.18 — the overlap is real, so this is deliberately set
  /// past most sound seed rather than at the class midpoint.
  static const double _highCrackRatio = 0.30;

  QualityPrediction classify(SeedFeatures features) {
    final evidence = <EvidenceFactor>[];
    final anomalies = <String>[];
    double penalty = 0;

    // Damage / dark regions.
    if (features.damage.darkRegionRatio > _highDamageDarkRatio) {
      final strength = ((features.damage.darkRegionRatio - _highDamageDarkRatio) * 3).clamp(0.0, 1.0);
      penalty += 24 * strength;
      evidence.add(EvidenceFactor(
        description: 'Notable dark or off-colour surface regions',
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
          ((features.damage.crackLikeEdgeRatio - _highCrackRatio) * 2).clamp(0.0, 1.0);
      penalty += 20 * strength;
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

    final score = (100 - penalty).clamp(0.0, 100.0);
    final qualityClass = anomalies.isEmpty ? QualityClass.good : QualityClass.damaged;

    // Confidence reflects how far the total penalty is from the decision
    // region and how much evidence was collected, not a calibrated
    // probability — a rule engine has no real notion of calibrated
    // uncertainty (§20). Max penalty here is ~44; the boundary sits near
    // the first rule's minimum contribution.
    final decisiveness = ((penalty - 12).abs() / 12).clamp(0.0, 1.0);
    final confidence = (0.5 + 0.35 * decisiveness).clamp(0.0, 0.9);

    return QualityPrediction(
      qualityClass: qualityClass,
      score: score,
      confidence: confidence,
      evidence: evidence,
      anomalies: anomalies,
      modelVersion: AppVersions.visionModelVersion,
    );
  }
}
