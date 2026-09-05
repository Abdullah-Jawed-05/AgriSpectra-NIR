import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/entities/fusion_result.dart';
import '../domain/entities/scan.dart';
import '../domain/entities/seed_result.dart';
import '../domain/entities/spectral_measurement.dart';
import '../domain/value_objects/confidence_level.dart';
import '../domain/value_objects/quality_class.dart';

/// Builds a shareable PDF for one completed [Scan] (§40 of the build spec).
/// Generated on demand only — when the user taps "Save Report" on the
/// result screen — never automatically after a scan.
///
/// Colors are lifted from `core/theme/app_theme.dart` (`AppColors`) rather
/// than re-invented, so the report reads as the same product as the app.
class ScanReportPdf {
  const ScanReportPdf._();

  static const _ink = PdfColor.fromInt(0xFF171E1B);
  static const _inkMuted = PdfColor.fromInt(0xFF54615B);
  static const _inkFaint = PdfColor.fromInt(0xFF8B968F);
  static const _divider = PdfColor.fromInt(0xFFDDE3DF);
  static const _accent = PdfColor.fromInt(0xFF0E6E5D);
  static const _accentMuted = PdfColor.fromInt(0xFFDCEEE9);
  static const _good = PdfColor.fromInt(0xFF1B7A4C);
  static const _moderate = PdfColor.fromInt(0xFFB07A12);
  static const _low = PdfColor.fromInt(0xFFB0401E);
  static const _nir = PdfColor.fromInt(0xFF5B3FA0);
  static const _nirMuted = PdfColor.fromInt(0xFFEAE4F6);

  static Future<Uint8List> build({
    required Scan scan,
    SpectralMeasurement? spectral,
  }) async {
    final doc = pw.Document(
      title: 'AgriSpectra report ${scan.scanId}',
      author: 'AgriSpectra',
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 40, 36, 36),
        header: (context) => context.pageNumber == 1 ? pw.SizedBox() : _runningHeader(scan),
        footer: (context) => _footer(context),
        build: (context) => [
          _title(scan),
          pw.SizedBox(height: 20),
          _summaryRow(scan),
          pw.SizedBox(height: 20),
          _breakdownCard(scan),
          pw.SizedBox(height: 16),
          _scoreDistributionCard(scan),
          if (spectral != null) ...[
            pw.SizedBox(height: 16),
            _spectralCard(spectral),
          ],
          pw.SizedBox(height: 16),
          _modelVersionsCard(scan),
          pw.SizedBox(height: 20),
          _seedSectionTitle(scan),
          pw.SizedBox(height: 10),
          _seedGrid(scan),
          pw.SizedBox(height: 24),
          _disclaimer(),
        ],
      ),
    );

    return doc.save();
  }

  static pw.Widget _runningHeader(Scan scan) => pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 8),
        decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _divider))),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('AgriSpectra', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: _accent, fontSize: 11)),
            pw.Text(scan.scanId, style: const pw.TextStyle(color: _inkFaint, fontSize: 9)),
          ],
        ),
      );

  static pw.Widget _footer(pw.Context context) => pw.Column(
        children: [
          pw.Divider(color: _divider),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Preliminary visual screening report, not a certified lab result.',
                style: const pw.TextStyle(color: _inkFaint, fontSize: 8),
              ),
              pw.Text(
                'Page ${context.pageNumber} of ${context.pagesCount}',
                style: const pw.TextStyle(color: _inkFaint, fontSize: 8),
              ),
            ],
          ),
        ],
      );

  static pw.Widget _title(Scan scan) => pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('AgriSpectra', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: _accent, fontSize: 26)),
              pw.SizedBox(height: 2),
              pw.Text(
                'Seed Batch Assessment · ${scan.crop.toUpperCase()}',
                style: const pw.TextStyle(color: _inkMuted, fontSize: 12),
              ),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(_formatDate(scan.timestamp), style: const pw.TextStyle(color: _ink, fontSize: 10)),
              pw.SizedBox(height: 2),
              pw.Text(scan.scanId, style: const pw.TextStyle(color: _inkFaint, fontSize: 8)),
            ],
          ),
        ],
      );

  static pw.Widget _summaryRow(Scan scan) {
    final level = confidenceLevelFrom(scan.confidence);
    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        color: _accentMuted,
        borderRadius: pw.BorderRadius.circular(10),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Text('${scan.batchScore.round()}', style: pw.TextStyle(fontSize: 40, fontWeight: pw.FontWeight.bold, color: _accent)),
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 8, left: 4),
            child: pw.Text('/ 100', style: const pw.TextStyle(color: _inkMuted, fontSize: 14)),
          ),
          pw.Spacer(),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text('Confidence: ${level.label}', style: pw.TextStyle(color: _accent, fontWeight: pw.FontWeight.bold, fontSize: 12)),
              pw.SizedBox(height: 4),
              pw.Text(
                '${scan.batchStatistics.seedsAccepted} seeds analyzed · ${_modeLabel(scan.fusionResult.mode)}',
                style: const pw.TextStyle(color: _inkMuted, fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _breakdownCard(Scan scan) {
    final stats = scan.batchStatistics;
    final fusion = scan.fusionResult;
    return _card(
      title: 'Batch breakdown',
      child: pw.Column(
        children: [
          _row('Visual quality', fusion.visualScore.round().toString()),
          _row('NIR enhancement', fusion.nirScore != null ? fusion.nirScore!.round().toString() : 'unavailable'),
          _row('Batch uniformity', '${(stats.uniformity * 100).round()}%'),
          _row('Visible anomalies', '${stats.anomalyCount} seeds'),
          _row(
            'Batch purity',
            '${(stats.purityRatio * 100).round()}%'
                '${stats.impurityCount > 0 ? ' (${stats.impurityCount} non-seed)' : ''}',
          ),
          _row('Rejected (unusable)', '${stats.seedsRejected}'),
          if (stats.qualityClassCounts.isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 8),
              child: pw.Wrap(
                spacing: 6,
                runSpacing: 6,
                children: stats.qualityClassCounts.entries
                    .map((e) => _pill('${QualityClassLabel.fromStorageKey(e.key).label}: ${e.value}'))
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }

  static pw.Widget _scoreDistributionCard(Scan scan) {
    final histogram = scan.batchStatistics.scoreHistogram;
    final maxCount = histogram.isEmpty ? 1 : histogram.reduce((a, b) => a > b ? a : b).clamp(1, 1 << 30);
    return _card(
      title: 'Score distribution',
      child: pw.SizedBox(
        height: 70,
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < histogram.length; i++)
              pw.Expanded(
                child: pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 2),
                  child: pw.Column(
                    mainAxisAlignment: pw.MainAxisAlignment.end,
                    children: [
                      pw.Text('${histogram[i]}', style: const pw.TextStyle(fontSize: 7, color: _inkFaint)),
                      pw.SizedBox(height: 2),
                      pw.Container(
                        height: 40 * (histogram[i] / maxCount),
                        decoration: const pw.BoxDecoration(color: _accent),
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text('${i * 10}', style: const pw.TextStyle(fontSize: 6, color: _inkFaint)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static pw.Widget _spectralCard(SpectralMeasurement spectral) {
    final values = spectral.reflectance ?? spectral.rawValues;
    final maxV = values.isEmpty ? 1.0 : values.reduce((a, b) => a > b ? a : b).clamp(0.0001, double.infinity);
    return _card(
      title: 'NIR spectral reading',
      titleColor: _nir,
      titleTrailing: spectral.isSimulated
          ? pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: pw.BoxDecoration(color: _nirMuted, borderRadius: pw.BorderRadius.circular(4)),
              child: pw.Text('SIMULATED', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: _nir)),
            )
          : null,
      child: pw.SizedBox(
        height: 60,
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            for (final v in values)
              pw.Expanded(
                child: pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 0.5),
                  child: pw.Container(height: 50 * (v / maxV).clamp(0.02, 1.0), color: _nir),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static pw.Widget _modelVersionsCard(Scan scan) => _card(
        title: 'Model versions',
        child: pw.Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _pill('vision ${scan.visionModelVersion}'),
            ...scan.fusionResult.modelVersions.entries
                .where((e) => e.key != 'vision')
                .map((e) => _pill('${e.key} ${e.value}')),
            _pill('analysis ${scan.analysisVersion}'),
          ],
        ),
      );

  static pw.Widget _seedSectionTitle(Scan scan) =>
      pw.Text('Individual seeds (${scan.results.length})', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13, color: _ink));

  static pw.Widget _seedGrid(Scan scan) => pw.Wrap(
        spacing: 8,
        runSpacing: 8,
        children: scan.results.map(_seedCard).toList(),
      );

  static pw.Widget _seedCard(SeedResult result) {
    final prediction = result.prediction;
    return pw.Container(
      width: 96,
      padding: const pw.EdgeInsets.all(6),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _divider),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.ClipRRect(
            horizontalRadius: 4,
            verticalRadius: 4,
            child: pw.Image(pw.MemoryImage(result.cropPng), height: 70, width: 84, fit: pw.BoxFit.cover),
          ),
          pw.SizedBox(height: 4),
          pw.Text('${prediction.score.round()}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12, color: _ink)),
          pw.Text(prediction.qualityClass.label, style: pw.TextStyle(fontSize: 7, color: _classColor(prediction.qualityClass))),
        ],
      ),
    );
  }

  static pw.Widget _disclaimer() => pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(color: PdfColor.fromInt(0xFFF7F8F7), borderRadius: pw.BorderRadius.circular(6)),
        child: pw.Text(
          'AgriSpectra provides preliminary non-destructive seed-quality screening and is not '
          'a replacement for certified laboratory germination or seed-quality testing.',
          style: pw.TextStyle(fontStyle: pw.FontStyle.italic, color: _inkMuted, fontSize: 9),
        ),
      );

  static pw.Widget _card({
    required String title,
    required pw.Widget child,
    PdfColor? titleColor,
    pw.Widget? titleTrailing,
  }) =>
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: _divider),
          borderRadius: pw.BorderRadius.circular(8),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(title, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11, color: titleColor ?? _ink)),
                ?titleTrailing,
              ],
            ),
            pw.SizedBox(height: 8),
            child,
          ],
        ),
      );

  static pw.Widget _row(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(label, style: const pw.TextStyle(color: _inkMuted, fontSize: 10)),
            pw.Text(value, style: pw.TextStyle(color: _ink, fontSize: 10, fontWeight: pw.FontWeight.bold)),
          ],
        ),
      );

  static pw.Widget _pill(String text) => pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: pw.BoxDecoration(color: _accentMuted, borderRadius: pw.BorderRadius.circular(10)),
        child: pw.Text(text, style: pw.TextStyle(fontSize: 8, color: _accent, fontWeight: pw.FontWeight.bold)),
      );

  static PdfColor _classColor(QualityClass qualityClass) => switch (qualityClass) {
        QualityClass.good => _good,
        QualityClass.damaged || QualityClass.shriveled => _moderate,
        QualityClass.broken => _low,
        QualityClass.impurities || QualityClass.unknown => _inkFaint,
      };

  static String _modeLabel(AssessmentMode mode) => switch (mode) {
        AssessmentMode.cameraOnly => 'Camera-only assessment',
        AssessmentMode.nirOnly => 'NIR-only assessment',
        AssessmentMode.multimodal => 'Multimodal assessment',
      };

  static String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec', //
    ];
    final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year} · $hour12:$minute $ampm';
  }
}
