/// Visual-quality classes for barley seeds (§15 of the build spec, scoped
/// to the one crop AgriSpectra currently has a dataset for). These are
/// observable classes derived from appearance. Each one has a measured
/// growth-test germination rate (good 90%, damaged 65%, broken 0%,
/// shriveled 0%) held in `GerminationReference`; batch germination figures
/// come from there, not from renaming these classes to imply biological
/// status (e.g. "dead"/"alive").
///
/// The four per-seed quality classes — [good], [damaged], [broken],
/// [shriveled] — mirror the labelled folders of the barley reference set.
/// Seeds with the hull missing are filed under [damaged] (there were too
/// few to justify a separate class).
///
/// [broken] is the one class that gets close to a germination claim — a
/// physically severed seed is very unlikely to germinate — but the class
/// itself only asserts the observable physical fact (the seed is
/// fragmented). Downstream UI/report copy should describe it that way
/// ("broken/fragmented"), not assert a germination outcome directly.
///
/// [impurities] is not a seed-quality verdict at all — it marks a detected
/// object that is foreign matter (stones, chaff, stems, other-crop seeds).
/// The batch engine keeps these out of the per-seed quality aggregation and
/// reports them separately as a batch-purity metric
/// (see [BatchStatistics.purityRatio]).
///
/// [unknown] is an internal fallback (e.g. an unrecognised stored key), not
/// a class the classifier or UI presents as a real outcome.
enum QualityClass {
  good,
  damaged,
  broken,
  shriveled,
  impurities,
  unknown,
}

extension QualityClassLabel on QualityClass {
  String get label => switch (this) {
        QualityClass.good => 'Good',
        QualityClass.damaged => 'Damaged',
        QualityClass.broken => 'Broken',
        QualityClass.shriveled => 'Shriveled',
        QualityClass.impurities => 'Impurities',
        QualityClass.unknown => 'Unknown',
      };

  String get storageKey => switch (this) {
        QualityClass.good => 'GOOD',
        QualityClass.damaged => 'DAMAGED',
        QualityClass.broken => 'BROKEN',
        QualityClass.shriveled => 'SHRIVELED',
        QualityClass.impurities => 'IMPURITIES',
        QualityClass.unknown => 'UNKNOWN',
      };

  static QualityClass fromStorageKey(String key) => switch (key) {
        'GOOD' => QualityClass.good,
        'DAMAGED' => QualityClass.damaged,
        'BROKEN' => QualityClass.broken,
        'SHRIVELED' => QualityClass.shriveled,
        'IMPURITIES' => QualityClass.impurities,
        // Legacy keys from the pre-barley taxonomy (DISCOLORED, SHELL_FREE,
        // MOLD_SUSPECT, INSECT_DAMAGED) fall through to unknown here.
        _ => QualityClass.unknown,
      };
}
