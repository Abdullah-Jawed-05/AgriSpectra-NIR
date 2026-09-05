import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';

import '../database/daos/scan_dao.dart';
import '../domain/value_objects/quality_class.dart';

/// Packages every human-verified seed (from "Make Our App Better") into a
/// zip laid out exactly as `ml/scripts/prepare_dataset.py` expects:
/// `<crop>/<batch_id>/<LABEL>/<seed_id>.png`. The user unzips this straight
/// into `ml/data/raw/` on a PC — no manual re-sorting.
///
/// `batch_id` is derived from the scan's capture date (`app_YYYY-MM-DD`),
/// not tracked separately anywhere — every day of app usage becomes its
/// own collection batch automatically, which is what actually lets
/// `split_dataset.py` do a real group split once enough days accumulate
/// (see docs/DATASET_GUIDE.md).
///
/// Always exports the *entire* verified set, not just what's new since the
/// last export — simpler and safer than tracking export state, since the
/// user is expected to replace their local `raw/<crop>/` wholesale with
/// each new export rather than merge them by hand.
class TrainingDataExport {
  const TrainingDataExport._();

  static Future<File> buildZip(List<VerifiedSeedExport> seeds) async {
    final archive = Archive();
    for (final seed in seeds) {
      final batchId = 'app_${_dateKey(seed.scanTimestamp)}';
      final path = '${seed.crop}/$batchId/${seed.verifiedLabel.storageKey}/${seed.seedId}.png';
      archive.addFile(ArchiveFile.bytes(path, seed.cropPng));
    }

    final zipBytes = ZipEncoder().encode(archive);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/agrispectra_training_export_${DateTime.now().millisecondsSinceEpoch}.zip');
    await file.writeAsBytes(zipBytes);
    return file;
  }

  static String _dateKey(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}
