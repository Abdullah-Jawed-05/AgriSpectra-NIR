import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/spectral_measurement.dart';

/// Interactive discrete-channel spectral graph (§69). Points, not a
/// smooth curve, are the honest representation — the AS7265x has 18
/// discrete channels, not a continuous spectrum (§31/§32), so this must
/// never imply more resolution than the sensor has.
class SpectralGraph extends StatelessWidget {
  const SpectralGraph({super.key, required this.measurement, this.showRaw = false});

  final SpectralMeasurement measurement;
  final bool showRaw;

  @override
  Widget build(BuildContext context) {
    final values = showRaw ? measurement.rawValues : (measurement.reflectance ?? measurement.rawValues);
    final wavelengths = measurement.wavelengthsNm;

    final spots = <FlSpot>[
      for (var i = 0; i < values.length && i < wavelengths.length; i++) FlSpot(wavelengths[i], values[i]),
    ];

    final minY = values.isEmpty ? 0.0 : values.reduce((a, b) => a < b ? a : b);
    final maxY = values.isEmpty ? 1.0 : values.reduce((a, b) => a > b ? a : b);
    final pad = (maxY - minY).abs() * 0.15 + 0.001;

    return LineChart(
      LineChartData(
        minY: minY - pad,
        maxY: maxY + pad,
        gridData: FlGridData(
          horizontalInterval: (maxY - minY) / 4 == 0 ? 1 : (maxY - minY) / 4,
          getDrawingHorizontalLine: (_) => FlLine(color: AppColors.divider, strokeWidth: 1),
          drawVerticalLine: false,
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 34,
              getTitlesWidget: (value, meta) => Text(
                value.toStringAsFixed(2),
                style: TextStyle(fontSize: 9, color: AppColors.inkFaint),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              interval: 100,
              getTitlesWidget: (value, meta) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${value.toInt()}',
                  style: TextStyle(fontSize: 9, color: AppColors.inkFaint),
                ),
              ),
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => spots
                .map((s) => LineTooltipItem(
                      '${s.x.toInt()}nm\n${s.y.toStringAsFixed(3)}',
                      const TextStyle(color: Colors.white, fontSize: 11),
                    ))
                .toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: false,
            color: AppColors.nir,
            barWidth: 2,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(show: true, color: AppColors.nirMuted.withValues(alpha: 0.6)),
          ),
        ],
      ),
    );
  }
}
