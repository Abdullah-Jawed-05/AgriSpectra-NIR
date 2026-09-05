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

/// Seeds nobody has reviewed in "Make Our App Better" yet — shown as a
/// nudge on the home screen. `autoDispose` so it re-queries (rather than
/// showing a stale count) each time the home screen is revisited.
final unverifiedSeedCountProvider = FutureProvider.autoDispose<int>((ref) {
  return ref.watch(scanRepositoryProvider).unverifiedSeedCount();
});
