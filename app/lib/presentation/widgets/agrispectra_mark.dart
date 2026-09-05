import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// The AgriSpectra mark: a stylized seed silhouette crossed by a lighter
/// horizontal band — read as both a spectral scan pass and a nod to a real
/// seed's central crease. Vector, not a bitmap, so it stays crisp from a
/// small home-screen icon up to the PDF report header — see
/// `app/lib/export/scan_report_pdf.dart`, which draws the same shape.
///
/// The actual app icon (`android/`, `ios/`, `web/` — generated via
/// `flutter_launcher_icons`, see pubspec.yaml) uses an inverted, higher-
/// contrast version of this same mark for home-screen legibility; this
/// widget is the in-app/report treatment.
class AgriSpectraMark extends StatelessWidget {
  const AgriSpectraMark({super.key, this.size = 28, this.seedColor, this.bandColor});

  final double size;
  final Color? seedColor;
  final Color? bandColor;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _MarkPainter(
        seedColor: seedColor ?? AppColors.accent,
        bandColor: bandColor ?? AppColors.accentMuted,
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  _MarkPainter({required this.seedColor, required this.bandColor});
  final Color seedColor;
  final Color bandColor;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    Offset p(double x, double y) => Offset(x / 100 * w, y / 100 * h);

    final seedPath = Path()
      ..moveTo(p(50, 14).dx, p(50, 14).dy)
      ..cubicTo(p(71, 30).dx, p(71, 30).dy, p(71, 70).dx, p(71, 70).dy, p(50, 90).dx, p(50, 90).dy)
      ..cubicTo(p(29, 70).dx, p(29, 70).dy, p(29, 30).dx, p(29, 30).dy, p(50, 14).dx, p(50, 14).dy)
      ..close();

    canvas.drawPath(seedPath, Paint()..color = seedColor);

    canvas.save();
    canvas.clipPath(seedPath);
    canvas.drawRect(Rect.fromLTWH(p(20, 42).dx, p(20, 42).dy, w * 0.6, h * 0.11), Paint()..color = bandColor);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MarkPainter oldDelegate) =>
      oldDelegate.seedColor != seedColor || oldDelegate.bandColor != bandColor;
}
