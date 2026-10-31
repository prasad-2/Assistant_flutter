// Central app state (Provider). Holds cached lists loaded from the database
// plus UI preferences. Screens call the `refresh*` methods after changing data.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../db/app_database.dart';
import '../db/debt_repository.dart';
import '../db/loan_repository.dart';
import '../models/debt_models.dart';
import '../models/loan_models.dart';
import '../models/models.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/widget_bridge.dart';

class AppState extends ChangeNotifier {
  AppState(this.prefs) : auth = AuthService(prefs) {
    themeMode = ThemeMode.values[(prefs.getInt('theme') ?? 0).clamp(0, 2)];
    hideBalances = prefs.getBool('hide_balances') ?? false;
    hideInRecents = prefs.getBool('hide_in_recents') ?? true;
    seedLight = prefs.getInt('seed_light') ?? kDefaultSeed;
    seedDark = prefs.getInt('seed_dark'); // null = same colour as light mode
    bgOpacity = prefs.getDouble('bg_opacity') ?? 0.35;
    // start-of-day snapshot of the available balances (see _ensureDailySnapshot)
    final snap = prefs.getString('daily_snap');
    if (snap != null) {
      try {
        final m = jsonDecode(snap) as Map<String, dynamic>;
        _snapDate = m['date'] as String;
        _snapAvail = {
          for (final e in (m['avail'] as Map<String, dynamic>).entries)
            int.parse(e.key): (e.value as num).toInt()
        };
      } catch (_) {}
    }
    // per-account show/hide choices are stored as "id:1" (hidden) / "id:0" (shown)
    for (final e in prefs.getStringList('acc_hide') ?? <String>[]) {
      final p = e.split(':');
      if (p.length == 2) accountHide[int.parse(p[0])] = p[1] == '1';
    }
    collapsedAccounts = (prefs.getStringList('collapsed_accounts') ?? [])
        .map(int.parse)
        .toSet();
  }

  /// Default theme colour (teal).
  static const int kDefaultSeed = 0xFF009688;

  final SharedPreferences prefs;
  final AuthService auth; // app lock
  late final AuthService financeAuth = // separate lock for the Finance section
      AuthService(prefs, prefix: 'fin_lock');
  final AppDatabase _db = AppDatabase.instance;

  ThemeMode themeMode = ThemeMode.system;
  bool hideBalances = false;

  /// Hide the app in the recent-apps list + block screenshots (default on).
  bool hideInRecents = true;

  // ── appearance ──
  int seedLight = kDefaultSeed; // theme colour for light mode (ARGB)
  int? seedDark; // separate colour for dark mode, null = use seedLight
  Uint8List? bgBytes; // background image (PNG) or null
  double bgOpacity = 0.35; // 0.1 .. 1.0 visibility of the image

  /// Individual eye-button choices: account id -> hidden (true) / shown (false).
  /// Accounts without an entry follow the global [hideBalances] switch.
  final Map<int, bool> accountHide = {};

  /// Are the values of this account hidden right now?
  bool isHidden(int accountId) => accountHide[accountId] ?? hideBalances;

  /// Eye button on a card: flips only this account.
  Future<void> toggleAccountHidden(int accountId) async {
    accountHide[accountId] = !isHidden(accountId);
    await _saveAccountHide();
    notifyListeners();
  }

  Future<void> _saveAccountHide() => prefs.setStringList('acc_hide',
      accountHide.entries.map((e) => '${e.key}:${e.value ? 1 : 0}').toList());

  // ── daily limit: start-of-day snapshot ──
  String _snapDate = ''; // day the snapshot belongs to (y-m-d)
  Map<int, int> _snapAvail = {}; // accountId -> available at the start of the day
  Timer? _midnightTimer;

  /// Today's actual money out / in on the regular accounts (paise).
  int todayOut = 0;
  int todayIn = 0;

  static String _dateKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

  /// Takes the "12 am" snapshot of every account's available balance the
  /// first time the app (or the widget) runs on a new day, BEFORE the user
  /// changes anything that day, so it equals the balance at midnight.
  void _ensureDailySnapshot() {
    final today = _dateKey(DateTime.now());
    if (_snapDate == today) return;
    _snapDate = today;
    _snapAvail = {for (final x in summaries) x.account.id!: x.available};
    prefs.setString(
        'daily_snap',
        jsonEncode({
          'date': today,
          'avail': {for (final e in _snapAvail.entries) '${e.key}': e.value}
        }));
  }

  /// Wakes up just after midnight (if the app is open) so the limit renews
  /// at 12 am even without any user action.
  void _scheduleMidnight() {
    _midnightTimer?.cancel();
    final n = DateTime.now();
    final next = DateTime(n.year, n.month, n.day + 1, 0, 0, 2);
    _midnightTimer = Timer(next.difference(n), () async {
      await refreshFinance();
      _scheduleMidnight();
    });
  }

  /// Available balance of the regular accounts at the start of today.
  int get startOfDayAvailable => summaries
      .where((x) => x.account.isRegular)
      .fold<int>(0, (s, x) => s + (_snapAvail[x.account.id] ?? 0));

  /// The day's ORIGINAL daily limit (start-of-day available / days left).
  int get originalDailyLimit => (startOfDayAvailable / daysLeftInMonth).round();

  /// Sum of the AVAILABLE balances of all regular accounts.
  int get regularAvailable => summaries
      .where((x) => x.account.isRegular)
      .fold<int>(0, (s, x) => s + x.available);

  /// Days left in the current month INCLUDING today (28-Oct -> 4 days).
  int get daysLeftInMonth {
    final n = DateTime.now();
    return DateTime(n.year, n.month + 1, 0).day - n.day + 1;
  }

  /// Daily limit = regular accounts' available balance / days left this month.
  /// It follows every transaction during the day.
  int get dailyLimit => (regularAvailable / daysLeftInMonth).round();

  /// Ids of parent accounts whose child accounts are collapsed (Finance tab).
  Set<int> collapsedAccounts = {};

  /// Expands / collapses the children of [id] and remembers the choice.
  Future<void> toggleCollapsed(int id) async {
    if (!collapsedAccounts.add(id)) collapsedAccounts.remove(id);
    await prefs.setStringList(
        'collapsed_accounts', collapsedAccounts.map((e) => '$e').toList());
    notifyListeners();
  }

  Color get lightSeedColor => Color(seedLight);
  Color get darkSeedColor => Color(seedDark ?? seedLight);
  bool get hasBackground => bgBytes != null;

  List<AccountSummary> summaries = []; // accounts with balances (tree order)
  List<Account> accounts = []; // plain accounts (for dropdowns)
  List<Category> categories = [];
  List<LoanSummary> loans = []; // loan management
  List<DebtPerson> people = []; // debt management
  List<Todo> todos = [];
  List<TodoGroup> groups = [];

  /// Incremented whenever finance data changes; list widgets watch it to
  /// know when to reload their own queries.
  int financeVersion = 0;

  /// Loads everything (used at start-up and after a restore).
  Future<void> load() async {
    bgBytes = await _db.getSettingBlob('bg_image');
    await refreshFinance(notify: false);
    await refreshTodos(notify: false);
    notifyListeners();
    _scheduleMidnight();
    await rescheduleReminders();
  }

  /// Reloads finance data only (cheap; no alarm rescheduling). Used when the
  /// app returns to the foreground because the widget may have added data.
  Future<void> refreshAll() async {
    await refreshFinance(notify: false);
    await refreshTodos(notify: false);
    notifyListeners();
  }

  Future<void> refreshFinance({bool notify = true}) async {
    summaries = await _db.getSummaries();
    accounts = await _db.getAccounts();
    categories = await _db.getCategories();
    loans = await LoanRepository.instance.summaries();
    people = await DebtRepository.instance.people();
    _ensureDailySnapshot();
    await _loadTodayTotals();
    financeVersion++;
    if (notify) notifyListeners();
    WidgetBridge.refresh(); // home-screen widget shows recent transactions
  }

  /// Today's actual debits / credits on the regular accounts.
  Future<void> _loadTodayTotals() async {
    final regular = {
      for (final x in summaries)
        if (x.account.isRegular) x.account.id
    };
    final now = DateTime.now();
    final list = regular.isEmpty
        ? <TxnRecord>[]
        : await _db.queryTransactions(
            TxnFilter(from: now, to: now, status: 'actual'));
    todayOut = 0;
    todayIn = 0;
    for (final t in list) {
      if (!regular.contains(t.accountId)) continue;
      if (t.amount < 0) {
        todayOut += -t.amount;
      } else {
        todayIn += t.amount;
      }
    }
  }

  Future<void> refreshTodos({bool notify = true}) async {
    todos = await _db.getTodos();
    groups = await _db.getGroups();
    if (notify) notifyListeners();
    WidgetBridge.refresh(); // home-screen widget shows pending todos
  }

  /// Saves the theme and lets the home-screen widget follow it.
  Future<void> setTheme(ThemeMode m) async {
    themeMode = m;
    await prefs.setInt('theme', m.index);
    notifyListeners();
    WidgetBridge.refresh();
  }

  /// Saves the theme colour(s). [dark] == null means "same as light".
  Future<void> setSeedColors(int light, int? dark) async {
    seedLight = light;
    seedDark = dark;
    await prefs.setInt('seed_light', light);
    if (dark == null) {
      await prefs.remove('seed_dark');
    } else {
      await prefs.setInt('seed_dark', dark);
    }
    notifyListeners();
  }

  /// Stores (or removes, when null) the app-wide background image.
  Future<void> setBackground(Uint8List? bytes) async {
    await _db.setSettingBlob('bg_image', bytes);
    bgBytes = bytes;
    notifyListeners();
  }

  /// How strongly the background image shows (0.1 – 1.0).
  Future<void> setBgOpacity(double v) async {
    bgOpacity = v.clamp(0.1, 1.0);
    await prefs.setDouble('bg_opacity', bgOpacity);
    notifyListeners();
  }

  /// Saves the privacy option and applies it to the window immediately.
  Future<void> setHideInRecents(bool v) async {
    hideInRecents = v;
    await prefs.setBool('hide_in_recents', v);
    WidgetBridge.setSecure(v);
    notifyListeners();
  }

  Future<void> toggleHide() async {
    hideBalances = !hideBalances;
    // the global switch is the master: it clears the individual choices
    accountHide.clear();
    await _saveAccountHide();
    await prefs.setBool('hide_balances', hideBalances);
    notifyListeners();
    WidgetBridge.refresh(); // widget masks amounts when balances are hidden
  }

  // ── todos + reminders ──

  /// Makes the scheduled alarm match the todo: cancels the old alarm and
  /// schedules a new one only for pending todos with a future reminder time.
  Future<void> _syncReminder(Todo t) async {
    final ns = NotificationService.instance;
    await ns.cancel(t.id!);
    final at = t.reminderAt;
    if (!t.isDone && at != null && at.isAfter(DateTime.now())) {
      await ns.schedule(
        id: t.id!,
        title: t.title,
        body: t.notes.isNotEmpty ? t.notes : 'Todo reminder',
        when: at,
      );
    }
  }

  /// Re-creates every alarm (after start-up or a restore).
  Future<void> rescheduleReminders() async {
    await NotificationService.instance.cancelAll();
    for (final t in todos) {
      await _syncReminder(t);
    }
  }

  Future<void> saveTodo(Todo t) async {
    final id = await _db.saveTodo(t);
    await refreshTodos();
    await _syncReminder(todos.firstWhere((x) => x.id == id));
  }

  Future<void> setTodoDone(Todo t, bool done) async {
    await _db.setTodoDone(t.id!, done);
    await refreshTodos();
    final upd = todos.where((x) => x.id == t.id);
    if (upd.isNotEmpty) await _syncReminder(upd.first);
  }

  Future<void> deleteTodo(Todo t) async {
    await NotificationService.instance.cancel(t.id!);
    await _db.deleteTodo(t.id!);
    await refreshTodos();
  }
}
