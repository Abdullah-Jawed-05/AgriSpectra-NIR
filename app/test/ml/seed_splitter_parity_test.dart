import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:agrispectra/ml/seed_splitter.dart';
import 'package:flutter_test/flutter_test.dart';

/// Parity gate for the touching-seed splitter: the Dart `SeedSplitter`
/// must produce the exact same split as `ml/preprocessing/seed_splitter.py`
/// on the shared synthetic masks. Regenerate the fixture with
/// `python ml/scripts/gen_splitter_parity_fixture.py` whenever either
/// implementation changes on purpose.
void main() {
  final file = File('test/ml/fixtures/seed_splitter_parity.json');
  final cases = (jsonDecode(file.readAsStringSync()) as List).cast<Map<String, Object?>>();

  const splitter = SeedSplitter();

  for (final c in cases) {
    test('parity: ${c['name']}', () {
      final w = c['w'] as int;
      final h = c['h'] as int;
      final bits = base64Decode(c['mask_b64'] as String);
      final mask = Uint8List(w * h);
      for (var i = 0; i < mask.length; i++) {
        // np.packbits is MSB-first.
        final set = (bits[i >> 3] >> (7 - (i & 7))) & 1;
        mask[i] = set == 1 ? 255 : 0;
      }

      final parts = splitter.split(mask, w, h);
      final sizes = parts.map((p) => p.length).toList()..sort();

      expect(parts.length, c['part_count'], reason: '${c['name']} part count');
      expect(sizes, c['part_sizes'], reason: '${c['name']} part sizes');
    });
  }
}
