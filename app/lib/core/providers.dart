import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/scan_repository.dart';
import '../database/app_database.dart';

/// Overridden in main() once [AppDatabase.open] resolves, before the
/// widget tree is built — see main.dart. Nothing should read this before
/// that override is in place.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  throw UnimplementedError('appDatabaseProvider must be overridden in main()');
});

final scanRepositoryProvider = Provider<ScanRepository>((ref) {
  return ScanRepository(ref.watch(appDatabaseProvider));
});
