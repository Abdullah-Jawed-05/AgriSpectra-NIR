import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Score distribution histogram (§21 "possible charts: score histogram").
class BatchHistogramChart extends StatelessWidget {
  const BatchHistogramChart({super.key, required this.buckets});

  /// 10 buckets: [0-10), [10-20), ..., [90-100].
  final List<int> buckets;

  @override
  Widget build(BuildContext context) {
    final maxY = (buckets.isEmpty ? 1 : buckets.reduce((a, b) => a > b ? a : b)).toDouble();

    return BarChart(
      BarChartData(
        maxY: maxY <= 0 ? 1 : maxY * 1.2,
        alignment: BarChartAlignment.spaceAround,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              getTitlesWidget: (value, meta) {
                final bucket = value.toInt();
                if (bucket % 3 != 0 && bucket != 9) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${bucket * 10}',
                    style: TextStyle(fontSize: 9, color: AppColors.inkFaint),
                  ),
                );
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(enabled: true),
        barGroups: [
          for (var i = 0; i < buckets.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: buckets[i].toDouble(),
                  color: _colorForBucket(i),
                  width: 14,
                  borderRadius: BorderRadius.circular(3),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Color _colorForBucket(int bucket) {
    if (bucket >= 7) return AppColors.good;
    if (bucket >= 5) return AppColors.moderate;
    return AppColors.low;
  }
}
