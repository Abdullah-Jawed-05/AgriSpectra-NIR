import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/providers.dart';
import 'core/theme/app_theme.dart';
import 'database/app_database.dart';
import 'presentation/screens/crop_selection_screen.dart';
import 'presentation/screens/history_screen.dart';
import 'presentation/screens/home_screen.dart';
import 'presentation/screens/improve_app_screen.dart';
import 'presentation/screens/nir_device_screen.dart';
import 'presentation/screens/result_screen.dart';
import 'presentation/screens/scan_flow_screen.dart';
import 'presentation/screens/seed_detail_screen.dart';
import 'presentation/screens/settings_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Deliberately not awaited before runApp(): database opening is async
  // I/O (IndexedDB/OPFS on web, native sqlite elsewhere) and the app must
  // still paint something if it's slow or fails, rather than a blank
  // screen forever — see _Bootstrap below.
  //
  // No ProviderScope here: _Bootstrap creates the *only* ProviderScope,
  // once per state, so the success state's scope is the root one and its
  // `appDatabaseProvider` override actually takes effect. With an outer
  // ProviderScope + a nested override scope, providers that don't declare
  // `dependencies` (scanRepositoryProvider et al.) get hoisted to the
  // outer scope and read the un-overridden, throwing appDatabaseProvider.
  runApp(const _Bootstrap());
}

final _router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
    GoRoute(
      path: '/scan/crop',
      builder: (context, state) => const CropSelectionScreen(),
    ),
    GoRoute(
      path: '/scan/flow',
      builder: (context, state) => ScanFlowScreen(crop: state.extra as String),
    ),
    GoRoute(
      path: '/scan/result/:scanId',
      builder: (context, state) => ResultScreen(scanId: state.pathParameters['scanId']!),
    ),
    GoRoute(
      path: '/scan/result/:scanId/seed/:seedId',
      builder: (context, state) => SeedDetailScreen(
        scanId: state.pathParameters['scanId']!,
        seedId: state.pathParameters['seedId']!,
      ),
    ),
    GoRoute(path: '/history', builder: (context, state) => const HistoryScreen()),
    GoRoute(path: '/improve', builder: (context, state) => const ImproveAppScreen()),
    GoRoute(path: '/nir', builder: (context, state) => const NirDeviceScreen()),
    GoRoute(path: '/settings', builder: (context, state) => const SettingsScreen()),
  ],
);

/// Opens [AppDatabase] and shows a splash/error state until it's ready,
/// so a slow or failed database open (§58: "database failure" must be
/// handled, not crash the app) is visible feedback instead of a blank page.
class _Bootstrap extends StatefulWidget {
  const _Bootstrap();

  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  late Future<AppDatabase> _future;

  @override
  void initState() {
    super.initState();
    _future = AppDatabase.open();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppDatabase>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          // Distinct key from the ready scope: the transition fully
          // remounts the ProviderScope rather than mutating overrides on a
          // live container.
          return ProviderScope(
            key: const ValueKey('bootstrap-error'),
            child: MaterialApp(
              theme: AppTheme.light(),
              home: _BootstrapMessage(
                message: 'Could not open the local database:\n${snapshot.error}',
                onRetry: () => setState(() => _future = AppDatabase.open()),
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return ProviderScope(
            key: const ValueKey('bootstrap-loading'),
            child: MaterialApp(
              theme: AppTheme.light(),
              home: const _BootstrapMessage(message: 'Starting AgriSpectra…'),
            ),
          );
        }
        return ProviderScope(
          key: const ValueKey('bootstrap-ready'),
          overrides: [appDatabaseProvider.overrideWithValue(snapshot.data!)],
          child: const AgriSpectraApp(),
        );
      },
    );
  }
}

class _BootstrapMessage extends StatelessWidget {
  const _BootstrapMessage({required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onRetry == null) const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(message, textAlign: TextAlign.center),
              if (onRetry != null) ...[
                const SizedBox(height: 16),
                ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class AgriSpectraApp extends StatelessWidget {
  const AgriSpectraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'AgriSpectra',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      routerConfig: _router,
    );
  }
}
