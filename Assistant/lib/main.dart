// App entry points.
//
//  * main()         – the normal app
//  * quickAddMain() – a second entry point started by the Android home-screen
//                     widget (see android_patch/kotlin/QuickAddActivity.kt)
//                     that shows only an "add transaction / todo" dialog.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_init.dart';
import 'providers/app_state.dart';
import 'screens/main_shell.dart';
import 'screens/quick_add.dart';
import 'services/notification_service.dart';
import 'widgets/app_background.dart';
import 'widgets/app_lock_layer.dart';

const String kAppName = 'Assistant';

/// Normal app start. The UI is shown immediately; heavy initialisation runs
/// inside [Bootstrap] so a slow/failed start never ends in a crash.
void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    FlutterError.onError = (d) {
      FlutterError.presentError(d);
      debugPrint('FlutterError: ${d.exceptionAsString()}');
    };
    runApp(const Bootstrap());
  }, (e, st) => debugPrint('Uncaught: $e\n$st'));
}

/// Entry point used by the widget's quick-add activity.
/// `@pragma` keeps it from being removed by the compiler.
@pragma('vm:entry-point')
void quickAddMain() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    runApp(const QuickAddApp());
  }, (e, st) => debugPrint('Uncaught(quick add): $e\n$st'));
}

/// Material theme shared by the app and the quick-add screen.
///
/// [seed] is the user-chosen theme colour. When a background image is set
/// ([transparent] = true) scaffolds, app bars and the navigation bar become
/// see-through so the image shows behind every screen.
ThemeData buildTheme(Brightness b, Color seed, {bool transparent = false}) {
  final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: b);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: transparent ? Colors.transparent : scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor:
          transparent ? scheme.surface.withValues(alpha: .6) : scheme.surface,
      scrolledUnderElevation: 0,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor:
          transparent ? scheme.surface.withValues(alpha: .75) : null,
    ),
    // Rounded, filled text fields used by every form in the app.
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: .55),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary, width: 1.6)),
      errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.error, width: 1.2)),
      focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.error, width: 1.6)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
    ),
  );
}

/// Default colour used before the user picks one.
final Color kDefaultSeedColor = Color(AppState.kDefaultSeed);

/// Initialises database, notifications and state while showing a spinner
/// (or an error with a Retry button).
class Bootstrap extends StatefulWidget {
  const Bootstrap({super.key});
  @override
  State<Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<Bootstrap> {
  late Future<AppState> _future = initApp();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppState>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasData) {
          // Ask for the notification permission only once the UI is visible.
          WidgetsBinding.instance.addPostFrameCallback((_) => Future.delayed(
              const Duration(seconds: 1),
              () => NotificationService.instance.requestNotificationPermission()));
          return ChangeNotifierProvider.value(
              value: snap.data!, child: const MyApp());
        }
        return MaterialApp(
          title: kAppName,
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light, kDefaultSeedColor),
          darkTheme: buildTheme(Brightness.dark, kDefaultSeedColor),
          home: Scaffold(
            body: Center(
              child: snap.hasError
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.error_outline, size: 48),
                        const SizedBox(height: 12),
                        Text('Could not start the app:\n${snap.error}',
                            textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(
                            onPressed: () =>
                                setState(() => _future = initApp()),
                            child: const Text('Retry')),
                      ]),
                    )
                  : const CircularProgressIndicator(),
            ),
          ),
        );
      },
    );
  }
}

/// The real app. [AppLockLayer] (in `builder`) sits above every route, so the
/// lock screen also covers pushed pages.
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return MaterialApp(
      title: kAppName,
      debugShowCheckedModeBanner: false,
      themeMode: s.themeMode,
      theme: buildTheme(Brightness.light, s.lightSeedColor,
          transparent: s.hasBackground),
      darkTheme: buildTheme(Brightness.dark, s.darkSeedColor,
          transparent: s.hasBackground),
      // order: background image (bottom) -> app routes -> lock screen (top)
      builder: (context, child) =>
          AppBackground(child: AppLockLayer(child: child!)),
      home: const MainShell(),
    );
  }
}
