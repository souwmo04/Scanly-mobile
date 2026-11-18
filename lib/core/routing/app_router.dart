import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../features/folders/folder_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/library/library_screen.dart';
import '../../features/pdf_viewer/document_screen.dart';
import '../../features/scanner/scanner_screen.dart';
import '../../features/search/search_screen.dart';
import '../../features/settings/info_screens.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/shell/app_shell.dart';
import 'routes.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

GoRouter createRouter() => GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: Routes.home,
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          AppShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: Routes.home,
              builder: (context, state) => const HomeScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: Routes.files,
              builder: (context, state) => const LibraryScreen(),
              routes: [
                GoRoute(
                  path: 'folder/:id',
                  builder: (context, state) =>
                      FolderScreen(folderId: state.pathParameters['id']!),
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: Routes.search,
              builder: (context, state) => const SearchScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: Routes.settings,
              builder: (context, state) => const SettingsScreen(),
              routes: [
                GoRoute(
                  path: 'privacy',
                  builder: (context, state) => const PrivacyScreen(),
                ),
                GoRoute(
                  path: 'about',
                  builder: (context, state) => const AboutScreen(),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
    // Full-screen routes above the bottom navigation.
    GoRoute(
      path: Routes.scan,
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (context, state) =>
          const MaterialPage(fullscreenDialog: true, child: ScannerScreen()),
    ),
    GoRoute(
      path: '/document/:id',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => DocumentScreen(
        documentId: state.pathParameters['id']!,
        initialPage: int.tryParse(state.uri.queryParameters['page'] ?? ''),
      ),
    ),
  ],
);

/// One router for the app's lifetime.
final routerProvider = Provider<GoRouter>((ref) {
  final router = createRouter();
  ref.onDispose(router.dispose);
  return router;
});
