/// Computer-vision features extracted per seed (§13 of the build spec).
/// These are visual indicators only — see [QualityClass] docs for the
/// constraint against implying biological viability from any of these.
class GeometryFeatures {
  final double areaPx;
  final double perimeterPx;
  final double widthPx;
  final double lengthPx;
  final double aspectRatio;
  final double circularity;
  final double eccentricity;
  final double convexity;

  const GeometryFeatures({
    required this.areaPx,
    required this.perimeterPx,
    required this.widthPx,
    required this.lengthPx,
    required this.aspectRatio,
    required this.circularity,
    required this.eccentricity,
    required this.convexity,
  });

  Map<String, Object?> toJson() => {
        'area_px': areaPx,
        'perimeter_px': perimeterPx,
        'width_px': widthPx,
        'length_px': lengthPx,
        'aspect_ratio': aspectRatio,
        'circularity': circularity,
        'eccentricity': eccentricity,
        'convexity': convexity,
      };
}

class ColorFeatures {
  final double meanR, meanG, meanB;
  final double meanHue, meanSaturation, meanValue;
  final double meanLabL, meanLabA, meanLabB;
  final double colorVarianceRgb;
  final double discolorationRatio;

  const ColorFeatures({
    required this.meanR,
    required this.meanG,
    required this.meanB,
    required this.meanHue,
    required this.meanSaturation,
    required this.meanValue,
    required this.meanLabL,
    required this.meanLabA,
    required this.meanLabB,
    required this.colorVarianceRgb,
    required this.discolorationRatio,
  });

  Map<String, Object?> toJson() => {
        'mean_rgb': [meanR, meanG, meanB],
        'mean_hsv': [meanHue, meanSaturation, meanValue],
        'mean_lab': [meanLabL, meanLabA, meanLabB],
        'color_variance_rgb': colorVarianceRgb,
        'discoloration_ratio': discolorationRatio,
      };
}

class TextureFeatures {
  final double edgeDensity;
  final double entropy;
  final double surfaceIrregularity;
  final double localContrast;

  const TextureFeatures({
    required this.edgeDensity,
    required this.entropy,
    required this.surfaceIrregularity,
    required this.localContrast,
  });

  Map<String, Object?> toJson() => {
        'edge_density': edgeDensity,
        'entropy': entropy,
        'surface_irregularity': surfaceIrregularity,
        'local_contrast': localContrast,
      };
}

/// Heuristic damage indicators (§13 "Damage"). Each is a 0..1 evidence
/// strength, not a diagnosis.
class DamageIndicators {
  final double darkRegionRatio;
  final double crackLikeEdgeRatio;
  final double holeRatio;
  final double abnormalPigmentationScore;

  const DamageIndicators({
    required this.darkRegionRatio,
    required this.crackLikeEdgeRatio,
    required this.holeRatio,
    required this.abnormalPigmentationScore,
  });

  Map<String, Object?> toJson() => {
        'dark_region_ratio': darkRegionRatio,
        'crack_like_edge_ratio': crackLikeEdgeRatio,
        'hole_ratio': holeRatio,
        'abnormal_pigmentation_score': abnormalPigmentationScore,
      };
}

class SeedFeatures {
  final GeometryFeatures geometry;
  final ColorFeatures color;
  final TextureFeatures texture;
  final DamageIndicators damage;

  const SeedFeatures({
    required this.geometry,
    required this.color,
    required this.texture,
    required this.damage,
  });

  Map<String, Object?> toJson() => {
        'geometry': geometry.toJson(),
        'color': color.toJson(),
        'texture': texture.toJson(),
        'damage': damage.toJson(),
      };
}
