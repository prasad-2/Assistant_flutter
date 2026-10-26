// Shared start-up sequence used by BOTH entry points (the normal app and the
// home-screen widget's quick-add screen).
import 'package:shared_preferences/shared_preferences.dart';

import 'db/app_database.dart';
import 'providers/app_state.dart';
import 'services/notification_service.dart';

/// Opens the database, prepares notifications and loads the app state.
Future<AppState> initApp() async {
  final prefs = await SharedPreferences.getInstance();
  await AppDatabase.instance.db;
  await NotificationService.instance.init();
  final state = AppState(prefs);
  await state.load();
  return state;
}
