/// Visual-quality classes (§15 of the build spec, refined against a real
/// barley reference set). These are observable classes derived from
/// appearance only — they are NOT viability or germination labels. Do not
/// rename these to imply biological status (e.g. "dead"/"alive") without an
/// actual laboratory ground-truth dataset backing that claim (see
/// docs/VALIDATION.md).
///
/// [broken] is the one class that gets close to a germination claim — a
/// physically severed seed is very unlikely to germinate — but the class
/// itself only asserts the observable physical fact (the seed is
/// fragmented). Downstream UI/report copy should describe it that way
/// ("broken/fragmented"), not assert a germination outcome directly.
enum QualityClass {
  good,
  damaged,
  broken,
  discolored,
  shriveled,
  shellFree,
  moldSuspect,
  insectDamaged,
  unknown,
}

extension QualityClassLabel on QualityClass {
  String get label => switch (this) {
        QualityClass.good => 'Good',
        QualityClass.damaged => 'Damaged',
        QualityClass.broken => 'Broken',
        QualityClass.discolored => 'Discolored',
        QualityClass.shriveled => 'Shriveled',
        QualityClass.shellFree => 'Shell-free',
        QualityClass.moldSuspect => 'Mold-suspect',
        QualityClass.insectDamaged => 'Insect damage',
        QualityClass.unknown => 'Unknown',
      };

  String get storageKey => switch (this) {
        QualityClass.good => 'GOOD',
        QualityClass.damaged => 'DAMAGED',
        QualityClass.broken => 'BROKEN',
        QualityClass.discolored => 'DISCOLORED',
        QualityClass.shriveled => 'SHRIVELED',
        QualityClass.shellFree => 'SHELL_FREE',
        QualityClass.moldSuspect => 'MOLD_SUSPECT',
        QualityClass.insectDamaged => 'INSECT_DAMAGED',
        QualityClass.unknown => 'UNKNOWN',
      };

  static QualityClass fromStorageKey(String key) => switch (key) {
        'GOOD' => QualityClass.good,
        'DAMAGED' => QualityClass.damaged,
        'BROKEN' => QualityClass.broken,
        'DISCOLORED' => QualityClass.discolored,
        'SHRIVELED' => QualityClass.shriveled,
        'SHELL_FREE' => QualityClass.shellFree,
        'MOLD_SUSPECT' => QualityClass.moldSuspect,
        'INSECT_DAMAGED' => QualityClass.insectDamaged,
        _ => QualityClass.unknown,
      };
}
