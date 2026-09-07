import '../core/constants/app_constants.dart';
import '../domain/entities/quality_prediction.dart';
import '../domain/entities/seed_features.dart';
import '../domain/value_objects/quality_class.dart';

/// Model V0 (§43): a rule engine over the extracted [SeedFeatures], not a
/// trained model. It exists to prove the full pipeline works end-to-end
/// honestly, before a trained classifier (Model V1) is wired in — see
/// docs/ML_PIPELINE.md and docs/VALIDATION.md.
///
/// **Scope: V0 flags barley grains with dark / discoloured / off-colour
/// damage, and nothing else.** It was re-checked twice against the
/// parity-fixed features:
///
///  - 2026-09-07, on 154 single-seed dorsal-side photos: the shape branch
///    (`circularity < 0.55 || eccentricity > 0.85`) fired on essentially
///    every barley grain (they are naturally elongated), routing ~all to
///    `shriveled`; the discoloration branch was backwards; the hole branch
///    had no signal. All removed.
///  - 2026-09-08, on the "Front Split" set (healthy grains, ventral furrow
///    facing the camera): the surviving **crack-like edge-density** branch
///    fired on the natural husk venation and the ventral furrow — healthy
///    ventral grains score ~0.47 on it, *higher* than the median damaged
///    grain (~0.20). Edge density measures which face is up, not damage.
///    Removed.
///
/// What's left is `darkRegionRatio` — genuine dark spots, mould, rot,
/// discoloured patches. On the reference sets a `> 0.22` cutoff keeps
/// ~90% of sound grain (Front Split + old good) and catches ~50% of the
/// old Damaged/Broken. A modest, honest screening heuristic — not a
/// validated cutoff, and it does **not** detect cracks, splits, shrivel
/// or breakage. `broken`, `shriveled` and `impurities` are never returned
/// here: `impurities` is a batch-relative call handled by
/// `ImpurityDetector` after this runs; `broken` / `shriveled` need V1.
class RuleBasedClassifier {
  const RuleBasedClassifier();

  /// Fraction of the seed surface reading as dark / off-colour. The
  /// natural ventral furrow contributes a little (~0.08 median on healthy
  /// grains), so the cutoff sits well above that; real discoloured /
  /// mouldy damage runs much higher.
  static const double _highDamageDarkRatio = 0.22;

  QualityPrediction classify(SeedFeatures features) {
    final evidence = <EvidenceFactor>[];
    final anomalies = <String>[];
    double penalty = 0;

    // Dark / discoloured / off-colour regions — the only damage signal V0
    // has for barley. Deliberately NOT keying on edge density: barley's
    // husk venation and ventral furrow are high-edge natural features (see
    // the class doc).
    if (features.damage.darkRegionRatio > _highDamageDarkRatio) {
      final strength = ((features.damage.darkRegionRatio - _highDamageDarkRatio) * 2.5).clamp(0.0, 1.0);
      penalty += 40 * strength;
      evidence.add(EvidenceFactor(
        description: 'Dark, discoloured or off-colour surface regions',
        supportsGoodQuality: false,
        weight: strength,
      ));
      anomalies.add('dark_surface_regions');
    } else {
      evidence.add(const EvidenceFactor(
        description: 'Even, healthy surface colour',
        supportsGoodQuality: true,
        weight: 0.4,
      ));
      evidence.add(const EvidenceFactor(
        description: 'Surface lines and the central furrow read as normal grain features, not damage',
        supportsGoodQuality: true,
        weight: 0.2,
      ));
    }

    final score = (100 - penalty).clamp(0.0, 100.0);
    final qualityClass = anomalies.isEmpty ? QualityClass.good : QualityClass.damaged;

    // Confidence reflects how far the penalty is from the decision region,
    // not a calibrated probability (§20). One rule now, max penalty 40.
    final decisiveness = ((penalty - 10).abs() / 15).clamp(0.0, 1.0);
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
