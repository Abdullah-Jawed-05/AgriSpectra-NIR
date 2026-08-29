/// Visual-quality classes (§15 of the build spec). These are observable
/// classes derived from appearance only — they are NOT viability or
/// germination labels. Do not rename these to imply biological status
/// (e.g. "dead"/"alive") without an actual laboratory ground-truth dataset
/// backing that claim (see docs/VALIDATION.md).
enum QualityClass {
  good,
  damaged,
  discolored,
  shriveled,
  moldSuspect,
  insectDamaged,
  unknown,
}

extension QualityClassLabel on QualityClass {
  String get label => switch (this) {
        QualityClass.good => 'Good',
        QualityClass.damaged => 'Damaged',
        QualityClass.discolored => 'Discolored',
        QualityClass.shriveled => 'Shriveled',
        QualityClass.moldSuspect => 'Mold-suspect',
        QualityClass.insectDamaged => 'Insect damage',
        QualityClass.unknown => 'Unknown',
      };

  String get storageKey => switch (this) {
        QualityClass.good => 'GOOD',
        QualityClass.damaged => 'DAMAGED',
        QualityClass.discolored => 'DISCOLORED',
        QualityClass.shriveled => 'SHRIVELED',
        QualityClass.moldSuspect => 'MOLD_SUSPECT',
        QualityClass.insectDamaged => 'INSECT_DAMAGED',
        QualityClass.unknown => 'UNKNOWN',
      };

  static QualityClass fromStorageKey(String key) => switch (key) {
        'GOOD' => QualityClass.good,
        'DAMAGED' => QualityClass.damaged,
        'DISCOLORED' => QualityClass.discolored,
        'SHRIVELED' => QualityClass.shriveled,
        'MOLD_SUSPECT' => QualityClass.moldSuspect,
        'INSECT_DAMAGED' => QualityClass.insectDamaged,
        _ => QualityClass.unknown,
      };
}
