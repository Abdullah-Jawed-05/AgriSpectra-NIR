// Dev-only diagnostic, not part of the normal `flutter test` suite (it
// isn't named *_test.dart, so bare `flutter test` won't discover it).
//
// Runs the on-device vision pipeline over one image and dumps each
// detected seed's features as JSON, so they can be diffed against
// ml/scripts/parity_check.py's output for the same image — the
// Python<->Dart feature-parity check (see docs/ML_PIPELINE.md).
//
// Usage: flutter test test/tool/parity_check_dev.dart --dart-define=IMAGE_PATH=<path>
import 'dart:convert';
import 'dart:io';

import 'package:agrispectra/ml/feature_extractor.dart';
import 'package:agrispectra/ml/seed_finder.dart';
import 'package:image/image.dart' as img;

const _imagePath = String.fromEnvironment('IMAGE_PATH');

void main() {
  if (_imagePath.isEmpty) {
    stderr.writeln('Pass --dart-define=IMAGE_PATH=<path/to/image.jpg>');
    exit(1);
  }
  final bytes = File(_imagePath).readAsBytesSync();
  final image = img.decodeImage(bytes);
  if (image == null) {
    stderr.writeln('Could not decode image: $_imagePath');
    exit(1);
  }

  final finder = ClassicalCVSeedFinder();
  final extractor = FeatureExtractor();
  final segmented = finder.find(image);

  final out = segmented.map((seed) {
    final features = extractor.extract(seed);
    final json = features.toJson();
    final geometry = (json['geometry'] as Map).cast<String, Object?>();
    final color = (json['color'] as Map).cast<String, Object?>();
    final texture = (json['texture'] as Map).cast<String, Object?>();
    final damage = (json['damage'] as Map).cast<String, Object?>();
    final rgb = (color['mean_rgb'] as List).cast<num>();
    final hsv = (color['mean_hsv'] as List).cast<num>();
    final lab = (color['mean_lab'] as List).cast<num>();

    return {
      'seed_id': seed.seedId,
      'center_x': seed.center.dx,
      'center_y': seed.center.dy,
      'bbox': [seed.boundingBox.left, seed.boundingBox.top, seed.boundingBox.width, seed.boundingBox.height],
      'area_px': geometry['area_px'],
      'perimeter_px': geometry['perimeter_px'],
      'width_px': geometry['width_px'],
      'length_px': geometry['length_px'],
      'aspect_ratio': geometry['aspect_ratio'],
      'circularity': geometry['circularity'],
      'eccentricity': geometry['eccentricity'],
      'convexity': geometry['convexity'],
      'mean_r': rgb[0],
      'mean_g': rgb[1],
      'mean_b': rgb[2],
      'mean_hue': hsv[0],
      'mean_saturation': hsv[1],
      'mean_value': hsv[2],
      'mean_lab_l': lab[0],
      'mean_lab_a': lab[1],
      'mean_lab_b': lab[2],
      'color_variance_rgb': color['color_variance_rgb'],
      'discoloration_ratio': color['discoloration_ratio'],
      'edge_density': texture['edge_density'],
      'entropy': texture['entropy'],
      'surface_irregularity': texture['surface_irregularity'],
      'local_contrast': texture['local_contrast'],
      'dark_region_ratio': damage['dark_region_ratio'],
      'crack_like_edge_ratio': damage['crack_like_edge_ratio'],
      'hole_ratio': damage['hole_ratio'],
      'abnormal_pigmentation_score': damage['abnormal_pigmentation_score'],
    };
  }).toList();

  // ignore: avoid_print
  print(const JsonEncoder.withIndent('  ').convert(out));
}
