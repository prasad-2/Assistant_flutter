// Local SQLite database (sqflite) – the single source of truth of the app.
//
// Layout of this file
//   1. Balance model (Ledger / availableOf)
//   2. Open / create / migrate
//   3. Balances + validation
//   4. Accounts
//   5. Categories
//   6. Transactions
//   7. Todos
//
// Every method that changes money-related data runs inside a DB transaction
// and ends with `_validate`, so an invalid change is rolled back completely.
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/models.dart';

/// Funds-block behaviour: scheduled DEBITS always reduce the available balance.
/// Set to true if you also want scheduled CREDITS to increase available balance.
const bool kScheduledCreditsCountInAvailable = false;

/// Raw sums of one account's transactions.
class Ledger {
  int actual = 0; // sum of actual transactions (signed)
  int schedDebit = 0; // sum of scheduled debits (negative number)
  int schedCredit = 0; // sum of scheduled credits (positive number)
  int get schedNet => schedDebit + schedCredit;
}

/// Available balance of an account: actual money minus funds blocked by
/// scheduled debits (plus the credit limit for credit accounts).
int availableOf(Account a, Ledger l) =>
    l.actual +
    l.schedDebit +
    (kScheduledCreditsCountInAvailable ? l.schedCredit : 0) +
    (a.isCredit ? a.creditLimit : 0);

/// Internal signal used to roll back a "dry run" transaction.
class _Rollback implements Exception {
  final String? error;
  _Rollback(this.error);
}

class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  static const _fileName = 'finance_todo.db';
  static const _version = 6;

  /// Shared open-future so concurrent callers never open the file twice.
  Future<Database>? _opening;

  Future<String> get path async => join(await getDatabasesPath(), _fileName);

  /// The opened database (opened lazily, once).
  Future<Database> get db => _opening ??= _openSafe();

  /// Opens the database, retrying once (first-install hiccups), and resets
  /// the cached future on failure so the next call can try again.
  Future<Database> _openSafe() async {
    try {
      try {
        return await _open();
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
        return await _open();
      }
    } catch (e) {
      _opening = null;
      rethrow;
    }
  }

  Future<Database> _open() async {
    final p = await path;
    await Directory(dirname(p)).create(recursive: true);
    return openDatabase(p,
        version: _version, onCreate: _create, onUpgrade: _upgrade);
  }

  /// Closes the database (used by backup / restore to flush the file).
  Future<void> close() async {
    final o = _opening;
    _opening = null;
    if (o != null) {
      try {
        await (await o).close();
      } catch (_) {}
    }
  }

  // ───────────────────────── schema ─────────────────────────

  /// Default categories: [name, type, icon].
  static const _seedCategories = <List<String>>[
    ['Self Transfer', 'transfer', 'swap_horiz'],
    ['Credit Bill Repayment', 'repayment', 'credit_card'],
    ['Opening Balance', 'credit', 'account_balance'],
    ['Salary', 'credit', 'payments'],
    ['Interest', 'credit', 'savings'],
    ['Refund', 'credit', 'redeem'],
    ['Other Income', 'credit', 'attach_money'],
    ['Shopping', 'debit', 'shopping_bag'],
    ['Food & Dining', 'debit', 'restaurant'],
    ['Bills & Utilities', 'debit', 'receipt_long'],
    ['Transport', 'debit', 'directions_bus'],
    ['Rent', 'debit', 'home'],
    ['Medical', 'debit', 'medical_services'],
    ['Entertainment', 'debit', 'movie'],
    ['Other Expense', 'debit', 'more_horiz'],
    ['Emi Payment', 'debit', 'account_balance'], // used by loan EMI payments
    ['Debt Given', 'debit', 'volunteer_activism'], // money lent to a friend
    ['Debt Received', 'credit', 'redeem'], // money borrowed from a friend
  ];

  /// Creates all tables for a brand new installation.
  Future<void> _create(Database d, int v) async {
    await d.execute('''CREATE TABLE accounts(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      owner TEXT NOT NULL,
      color INTEGER NOT NULL,
      parent_id INTEGER,
      is_credit INTEGER NOT NULL DEFAULT 0,
      credit_limit INTEGER NOT NULL DEFAULT 0,
      is_regular INTEGER NOT NULL DEFAULT 0,
      notes TEXT,
      icon_key TEXT,
      icon_blob BLOB,
      sort_order INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL)''');
    await d.execute('''CREATE TABLE categories(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      type TEXT NOT NULL,
      icon TEXT)''');
    // amount is SIGNED paise; sched_* columns keep the original schedule.
    await d.execute('''CREATE TABLE transactions(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      account_id INTEGER NOT NULL,
      category_id INTEGER NOT NULL,
      description TEXT NOT NULL,
      date_time INTEGER NOT NULL,
      amount INTEGER NOT NULL,
      status TEXT NOT NULL,
      transfer_group TEXT,
      sched_date_time INTEGER,
      sched_description TEXT,
      sched_amount INTEGER,
      completed_at INTEGER,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL)''');
    await d.execute('CREATE INDEX idx_txn_acc ON transactions(account_id)');
    await d.execute('CREATE INDEX idx_txn_date ON transactions(date_time)');
    await d.execute('''CREATE TABLE todo_groups(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL)''');
    await d.execute('''CREATE TABLE todos(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT NOT NULL,
      notes TEXT,
      group_id INTEGER,
      due_at INTEGER,
      reminder INTEGER NOT NULL DEFAULT 0,
      reminder_offset INTEGER NOT NULL DEFAULT 0,
      is_done INTEGER NOT NULL DEFAULT 0,
      completed_at INTEGER,
      created_at INTEGER NOT NULL)''');

    await _createSettingsTable(d);
    await _createLoanDebtTables(d);

    for (final s in _seedCategories) {
      await d.insert('categories', {'name': s[0], 'type': s[1], 'icon': s[2]});
    }
  }

  /// Loan management + debt management tables (added in schema v5).
  Future<void> _createLoanDebtTables(Database d) async {
    await d.execute('''CREATE TABLE IF NOT EXISTS loans(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      color INTEGER NOT NULL,
      icon_key TEXT,
      icon_blob BLOB,
      principal INTEGER NOT NULL,
      rate REAL NOT NULL,
      tenure_value INTEGER NOT NULL,
      tenure_unit TEXT NOT NULL,
      start_date INTEGER NOT NULL,
      freq_value INTEGER NOT NULL,
      freq_unit TEXT NOT NULL,
      foreclose_pct REAL NOT NULL DEFAULT 0,
      penalty_pct REAL NOT NULL DEFAULT 0,
      emi_amount INTEGER NOT NULL DEFAULT 0,
      notes TEXT,
      status TEXT NOT NULL DEFAULT 'active',
      created_at INTEGER NOT NULL)''');
    await d.execute('''CREATE TABLE IF NOT EXISTS loan_emis(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      loan_id INTEGER NOT NULL,
      no INTEGER NOT NULL,
      due_date INTEGER NOT NULL,
      emi INTEGER NOT NULL,
      principal_part INTEGER NOT NULL,
      interest_part INTEGER NOT NULL,
      status TEXT NOT NULL DEFAULT 'pending',
      paid_date INTEGER,
      penalty INTEGER NOT NULL DEFAULT 0,
      txn_id INTEGER)''');
    await d.execute('''CREATE TABLE IF NOT EXISTS debt_people(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL)''');
    await d.execute('''CREATE TABLE IF NOT EXISTS debt_entries(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      person_id INTEGER NOT NULL,
      description TEXT NOT NULL,
      date_time INTEGER NOT NULL,
      amount INTEGER NOT NULL,
      direction TEXT NOT NULL,
      is_setoff INTEGER NOT NULL DEFAULT 0,
      txn_id INTEGER,
      created_at INTEGER NOT NULL)''');
  }

  /// Key/value store for binary settings (e.g. the app background image).
  /// Living inside the database means backups include them.
  Future<void> _createSettingsTable(Database d) => d.execute(
      'CREATE TABLE IF NOT EXISTS app_settings(key TEXT PRIMARY KEY, value BLOB)');

  /// Upgrades an existing database (also runs for restored old backups).
  ///   v1 -> v2: account notes + icons, category icons.
  ///   v2 -> v3: app_settings table (background image).
  ///   v3 -> v4: built-in "Credit Bill Repayment" category.
  ///   v4 -> v5: loans, loan EMIs, debts + Emi Payment / Debt categories.
  ///   v5 -> v6: accounts.sort_order (user defined card order).
  Future<void> _upgrade(Database d, int oldV, int newV) async {
    if (oldV < 2) {
      await d.execute('ALTER TABLE accounts ADD COLUMN notes TEXT');
      await d.execute('ALTER TABLE accounts ADD COLUMN icon_key TEXT');
      await d.execute('ALTER TABLE accounts ADD COLUMN icon_blob BLOB');
      await d.execute('ALTER TABLE categories ADD COLUMN icon TEXT');
      for (final s in _seedCategories) {
        await d.update('categories', {'icon': s[2]},
            where: 'name=? AND icon IS NULL', whereArgs: [s[0]]);
      }
      await d.update('categories', {'icon': 'category'},
          where: 'icon IS NULL');
    }
    if (oldV < 3) {
      await _createSettingsTable(d);
    }
    if (oldV < 4) {
      final has = await d.query('categories', where: "type='repayment'");
      if (has.isEmpty) {
        // avoid a name clash with a category the user may have created
        final clash = await d.query('categories',
            where: 'LOWER(name)=?', whereArgs: ['credit bill repayment']);
        await d.insert('categories', {
          'name': clash.isEmpty
              ? 'Credit Bill Repayment'
              : 'Credit Bill Repayment (system)',
          'type': 'repayment',
          'icon': 'credit_card',
        });
      }
    }
    if (oldV < 6) {
      await d.execute(
          'ALTER TABLE accounts ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0');
      // keep today's (alphabetical) order as the starting order per parent
      final rows = await d.query('accounts',
          columns: ['id', 'parent_id'], orderBy: 'LOWER(name)');
      final counters = <int?, int>{};
      for (final r in rows) {
        final p = r['parent_id'] as int?;
        final n = counters[p] ?? 0;
        counters[p] = n + 1;
        await d.update('accounts', {'sort_order': n},
            where: 'id=?', whereArgs: [r['id']]);
      }
    }
    if (oldV < 5) {
      await _createLoanDebtTables(d);
      for (final s in _seedCategories.skip(_seedCategories.length - 3)) {
        final has = await d.query('categories',
            where: 'LOWER(name)=?', whereArgs: [s[0].toLowerCase()]);
        if (has.isEmpty) {
          await d.insert('categories', {'name': s[0], 'type': s[1], 'icon': s[2]});
        }
      }
    }
  }

  /// Id of the category called [name]; creates it when missing. Used by the
  /// loan / debt features for their automatic bank transactions. Throws when
  /// the user changed the category to the wrong type (it would flip signs).
  Future<int> categoryIdByName(String name, String type, String icon) async {
    final d = await db;
    final r = await d.query('categories',
        where: 'LOWER(name)=?', whereArgs: [name.toLowerCase()]);
    if (r.isNotEmpty) {
      if (r.first['type'] != type) {
        throw ValidationException(
            'The category "$name" must be of type ${type == 'debit' ? 'Deduct' : 'Credit'} for this feature. Fix it in Settings → Transaction categories.');
      }
      return r.first['id'] as int;
    }
    return d.insert('categories', {'name': name, 'type': type, 'icon': icon});
  }

  /// Clears loan / debt links that point at bank transactions about to be
  /// deleted (matching `transactions WHERE [where]`).
  Future<void> _unlinkTxns(DatabaseExecutor t, String where, List<Object?> args) async {
    for (final table in ['debt_entries', 'loan_emis']) {
      await t.rawUpdate(
          'UPDATE $table SET txn_id=NULL WHERE txn_id IN (SELECT id FROM transactions WHERE $where)',
          args);
    }
  }

  // ───────────────────────── binary settings ─────────────────────────

  /// Reads a binary setting (null when not set).
  Future<Uint8List?> getSettingBlob(String key) async {
    final r = await (await db)
        .query('app_settings', where: 'key=?', whereArgs: [key]);
    return r.isEmpty ? null : r.first['value'] as Uint8List?;
  }

  /// Stores (or, when [value] is null, removes) a binary setting.
  Future<void> setSettingBlob(String key, Uint8List? value) async {
    final d = await db;
    if (value == null) {
      await d.delete('app_settings', where: 'key=?', whereArgs: [key]);
    } else {
      await d.insert('app_settings', {'key': key, 'value': value},
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  // ───────────────────────── balances ─────────────────────────

  Future<List<Account>> _accounts(DatabaseExecutor e) async =>
      (await e.query('accounts', orderBy: 'id')).map(Account.fromMap).toList();

  Future<List<Account>> getAccounts() async => _accounts(await db);

  /// Sums every account's transactions in one query: accountId -> [Ledger].
  Future<Map<int, Ledger>> _ledgers(DatabaseExecutor e) async {
    final rows = await e.rawQuery(
        'SELECT account_id, status, '
        'SUM(CASE WHEN amount<0 THEN amount ELSE 0 END) AS neg, '
        'SUM(CASE WHEN amount>0 THEN amount ELSE 0 END) AS pos '
        'FROM transactions GROUP BY account_id, status');
    final map = <int, Ledger>{};
    for (final r in rows) {
      final l = map.putIfAbsent(r['account_id'] as int, () => Ledger());
      final neg = (r['neg'] as num?)?.toInt() ?? 0;
      final pos = (r['pos'] as num?)?.toInt() ?? 0;
      if (r['status'] == 'actual') {
        l.actual += neg + pos;
      } else {
        l.schedDebit += neg;
        l.schedCredit += pos;
      }
    }
    return map;
  }

  /// Builds the account list (depth-first tree order) with calculated balances.
  ///
  ///  * available = own ledger minus scheduled debits
  ///  * actual    = own ledger + the ledgers of ALL nested child accounts
  /// Example: HDFC 1000 opening, 600 -> "daily use", 150 -> "savings":
  ///   HDFC actual 1000 / available 250; children actual == available.
  Future<List<AccountSummary>> getSummaries() async {
    final d = await db;
    final accs = await _accounts(d);
    final led = await _ledgers(d);
    final byId = {for (final a in accs) a.id!: a};

    // parent id -> children (null key = top level accounts)
    final children = <int?, List<Account>>{};
    for (final a in accs) {
      final p = (a.parentId != null && byId.containsKey(a.parentId))
          ? a.parentId
          : null;
      children.putIfAbsent(p, () => []).add(a);
    }
    for (final l in children.values) {
      // user defined order first, then name
      l.sort((a, b) => a.sortOrder != b.sortOrder
          ? a.sortOrder.compareTo(b.sortOrder)
          : a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }

    // ledger of an account + all descendants (memoised)
    final cache = <int, int>{};
    int aggregate(Account a) => cache[a.id!] ??= (led[a.id]?.actual ?? 0) +
        (children[a.id] ?? const <Account>[])
            .fold<int>(0, (s, c) => s + aggregate(c));

    final out = <AccountSummary>[];
    void walk(int? parent, int depth) {
      for (final a in children[parent] ?? const <Account>[]) {
        final l = led[a.id] ?? Ledger();
        out.add(AccountSummary(
          account: a,
          depth: depth,
          parentName: byId[a.parentId]?.name,
          hasChildren: (children[a.id] ?? const <Account>[]).isNotEmpty,
          actual: aggregate(a) + (a.isCredit ? a.creditLimit : 0),
          available: availableOf(a, l),
          scheduledIn: l.schedCredit,
          scheduledOut: -l.schedDebit,
        ));
        walk(a.id, depth + 1);
      }
    }

    walk(null, 0);
    return out;
  }

  /// Available balance of every account (accountId -> paise). Taken BEFORE a
  /// change so [_validate] can tell whether the change made things worse.
  Future<Map<int, int>> _availableMap(DatabaseExecutor e) async {
    final accs = await _accounts(e);
    final led = await _ledgers(e);
    return {
      for (final a in accs) a.id!: availableOf(a, led[a.id] ?? Ledger())
    };
  }

  /// Re-checks every account after a change. Throws [ValidationException]
  /// (which rolls the whole DB transaction back) when:
  ///  * an ACTUAL balance would be negative / a credit limit exceeded, always;
  ///  * an AVAILABLE balance would be negative AND the change lowered it.
  ///    Scheduled transactions are allowed to push the available balance
  ///    below zero: pass [skipAvailable] = true for such changes. Already
  ///    negative balances do not block unrelated changes.
  Future<void> _validate(DatabaseExecutor e,
      {Map<int, int>? before, bool skipAvailable = false}) async {
    final accs = await _accounts(e);
    final led = await _ledgers(e);
    for (final a in accs) {
      final l = led[a.id] ?? Ledger();
      final lim = a.isCredit ? a.creditLimit : 0;
      if (l.actual + lim < 0) {
        throw ValidationException(a.isCredit
            ? 'Insufficient balance: this would exceed the credit limit of "${a.name}".'
            : 'Insufficient balance in "${a.name}": the actual balance would become negative.');
      }
      if (skipAvailable) continue;
      final avail = availableOf(a, l);
      final worse = before == null || avail < (before[a.id] ?? avail);
      if (avail < 0 && worse) {
        throw ValidationException(
            'Insufficient available balance in "${a.name}": funds blocked by scheduled transactions are needed for this.');
      }
    }
  }

  /// Credit bill repayment rule: pay FROM a non-credit account TO a credit one.
  Future<void> _checkRepayment(DatabaseExecutor t, TxnInput i) async {
    Future<Account?> acc(int? id) async {
      if (id == null) return null;
      final r = await t.query('accounts', where: 'id=?', whereArgs: [id]);
      return r.isEmpty ? null : Account.fromMap(r.first);
    }

    final from = await acc(i.accountId);
    final to = await acc(i.toAccountId);
    if (from == null || to == null) {
      throw ValidationException('Select both accounts.');
    }
    if (from.isCredit) {
      throw ValidationException(
          'A credit bill is paid FROM a normal (non-credit) account.');
    }
    if (!to.isCredit) {
      throw ValidationException('A credit bill is paid TO a credit account.');
    }
  }

  // ───────────────────────── accounts ─────────────────────────

  /// Inserts or updates an account. Validates name, credit limit, parent
  /// cycles and finally all balances. Returns the account id.
  Future<int> saveAccount(Account a) async {
    final d = await db;
    return d.transaction((t) async {
      if (a.name.trim().isEmpty) {
        throw ValidationException('Bank name is required.');
      }
      if (a.owner.trim().isEmpty) {
        throw ValidationException('Owner name is required.');
      }
      if (a.isCredit && a.creditLimit <= 0) {
        throw ValidationException('Credit limit must be greater than zero.');
      }
      // names must be unique (case-insensitive)
      final dup = await t.query('accounts',
          where: a.id == null
              ? 'LOWER(name)=?'
              : 'LOWER(name)=? AND id<>${a.id}',
          whereArgs: [a.name.trim().toLowerCase()]);
      if (dup.isNotEmpty) {
        throw ValidationException(
            'An account named "${a.name.trim()}" already exists.');
      }
      // an account may not become its own ancestor: walk up from the parent
      if (a.parentId != null) {
        if (a.id != null && a.parentId == a.id) {
          throw ValidationException('An account cannot be its own parent.');
        }
        int? cur = a.parentId;
        var guard = 0;
        while (cur != null && guard++ < 1000) {
          if (a.id != null && cur == a.id) {
            throw ValidationException(
                'Invalid parent: it is a child (descendant) of this account.');
          }
          final r = await t.query('accounts',
              columns: ['parent_id'], where: 'id=?', whereArgs: [cur]);
          cur = r.isEmpty ? null : r.first['parent_id'] as int?;
        }
      }
      final before = await _availableMap(t);
      // next free position among the siblings of the (new) parent
      Future<int> nextOrder() async {
        final r = await t.rawQuery(
            a.parentId == null
                ? 'SELECT COALESCE(MAX(sort_order),-1)+1 AS n FROM accounts WHERE parent_id IS NULL'
                : 'SELECT COALESCE(MAX(sort_order),-1)+1 AS n FROM accounts WHERE parent_id=?',
            a.parentId == null ? [] : [a.parentId]);
        return (r.first['n'] as num).toInt();
      }

      int id;
      if (a.id == null) {
        final m = a.toMap();
        m['created_at'] = DateTime.now().millisecondsSinceEpoch;
        m['sort_order'] = await nextOrder();
        id = await t.insert('accounts', m);
      } else {
        final m = a.toMap(); // toMap never contains sort_order: it is kept
        final old = await t.query('accounts',
            columns: ['parent_id'], where: 'id=?', whereArgs: [a.id]);
        if (old.isNotEmpty && old.first['parent_id'] != a.parentId) {
          m['sort_order'] = await nextOrder(); // moved to another parent
        }
        await t.update('accounts', m, where: 'id=?', whereArgs: [a.id]);
        id = a.id!;
      }
      // e.g. switching to a smaller credit limit may break balances
      await _validate(t, before: before);
      return id;
    });
  }

  /// Moves an account one step up / down among its siblings of the SAME type
  /// (same parent, both normal or both credit) and saves the new order.
  Future<void> moveAccount(int id, {required bool up}) async {
    final d = await db;
    await d.transaction((t) async {
      final accs = await _accounts(t);
      final me = accs.firstWhere((a) => a.id == id);
      final sibs = accs
          .where((a) => a.parentId == me.parentId && a.isCredit == me.isCredit)
          .toList()
        ..sort((a, b) => a.sortOrder != b.sortOrder
            ? a.sortOrder.compareTo(b.sortOrder)
            : a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      final i = sibs.indexWhere((a) => a.id == id);
      final j = up ? i - 1 : i + 1;
      if (j < 0 || j >= sibs.length) return;
      final tmp = sibs[i];
      sibs[i] = sibs[j];
      sibs[j] = tmp;
      for (var k = 0; k < sibs.length; k++) {
        await t.update('accounts', {'sort_order': k},
            where: 'id=?', whereArgs: [sibs[k].id]);
      }
    });
  }

  /// Toggles the "regular account" flag (shown on the home screen).
  Future<void> setRegular(int id, bool v) async =>
      (await db).update('accounts', {'is_regular': v ? 1 : 0},
          where: 'id=?', whereArgs: [id]);

  Future<int> accountTxnCount(int id) async => Sqflite.firstIntValue(
          await (await db).rawQuery(
              'SELECT COUNT(*) FROM transactions WHERE account_id=?', [id])) ??
      0;

  /// Deletes an account and its own transactions. Blocked while the account
  /// has children or self-transfer legs that other balances depend on.
  Future<void> deleteAccount(int id) async {
    final d = await db;
    await d.transaction((t) async {
      final before = await _availableMap(t);
      final kids = Sqflite.firstIntValue(await t.rawQuery(
              'SELECT COUNT(*) FROM accounts WHERE parent_id=?', [id])) ??
          0;
      if (kids > 0) {
        throw ValidationException(
            'This account has $kids child account(s). Delete or re-link them to another parent first.');
      }
      final tr = Sqflite.firstIntValue(await t.rawQuery(
              'SELECT COUNT(*) FROM transactions WHERE account_id=? AND transfer_group IS NOT NULL',
              [id])) ??
          0;
      if (tr > 0) {
        throw ValidationException(
            'This account has $tr self-transfer transaction(s) linked with other accounts. Delete those transfers first so other balances stay correct.');
      }
      await _unlinkTxns(t, 'account_id=?', [id]);
      await t.delete('transactions', where: 'account_id=?', whereArgs: [id]);
      await t.delete('accounts', where: 'id=?', whereArgs: [id]);
      await _validate(t, before: before);
    });
  }

  // ───────────────────────── categories ─────────────────────────

  /// All categories; the built-in Self Transfer first, rest alphabetical.
  Future<List<Category>> getCategories() async => (await (await db).query(
          'categories',
          orderBy:
              "CASE type WHEN 'transfer' THEN 0 WHEN 'repayment' THEN 1 ELSE 2 END, LOWER(name)"))
      .map(Category.fromMap)
      .toList();

  Future<Category> _category(DatabaseExecutor e, int id) async {
    final r = await e.query('categories', where: 'id=?', whereArgs: [id]);
    if (r.isEmpty) throw ValidationException('Category not found.');
    return Category.fromMap(r.first);
  }

  /// Number of transactions that use a category.
  Future<int> categoryUsageCount(int id) async => Sqflite.firstIntValue(
          await (await db).rawQuery(
              'SELECT COUNT(*) FROM transactions WHERE category_id=?', [id])) ??
      0;

  /// Applies an edit to an existing category. When the type flips between
  /// credit and deduct, the sign of all transactions of that category flips
  /// too (their balance impact changes), then balances are re-validated.
  Future<void> _applyCategory(DatabaseExecutor t, Category nc) async {
    final before = await _availableMap(t);
    final old = await _category(t, nc.id!);
    if (old.isSystem) {
      throw ValidationException(
          'Built-in categories (Self Transfer, Credit Bill Repayment) cannot be changed.');
    }
    if (nc.isSystem) {
      throw ValidationException('Invalid category type.');
    }
    final dup = await t.query('categories',
        where: 'LOWER(name)=? AND id<>?',
        whereArgs: [nc.name.trim().toLowerCase(), nc.id]);
    if (dup.isNotEmpty) {
      throw ValidationException('Category "${nc.name.trim()}" already exists.');
    }
    await t.update(
        'categories', {'name': nc.name.trim(), 'type': nc.type, 'icon': nc.icon},
        where: 'id=?', whereArgs: [nc.id]);
    if (old.type != nc.type) {
      await t.rawUpdate(
          'UPDATE transactions SET amount=-amount, sched_amount=-sched_amount, updated_at=? WHERE category_id=?',
          [DateTime.now().millisecondsSinceEpoch, nc.id]);
    }
    await _validate(t, before: before);
  }

  /// Dry run of a category edit. Returns an error message when saving would
  /// break balances, otherwise null. Nothing is persisted.
  Future<String?> simulateCategoryChange(Category nc) async {
    final d = await db;
    String? err;
    try {
      await d.transaction((t) async {
        try {
          await _applyCategory(t, nc);
        } on ValidationException catch (e) {
          err = e.message;
        }
        throw _Rollback(err); // always roll back the dry run
      });
    } on _Rollback {
      // expected
    }
    return err;
  }

  /// Adds (id == null) or edits a category.
  Future<void> saveCategory(Category c) async {
    final d = await db;
    await d.transaction((t) async {
      if (c.name.trim().isEmpty) {
        throw ValidationException('Category name is required.');
      }
      if (c.id == null) {
        final dup = await t.query('categories',
            where: 'LOWER(name)=?', whereArgs: [c.name.trim().toLowerCase()]);
        if (dup.isNotEmpty) {
          throw ValidationException('Category "${c.name.trim()}" already exists.');
        }
        await t.insert('categories',
            {'name': c.name.trim(), 'type': c.type, 'icon': c.icon});
      } else {
        await _applyCategory(t, c);
      }
    });
  }

  /// Deletes an unused, non built-in category.
  Future<void> deleteCategory(int id) async {
    final d = await db;
    await d.transaction((t) async {
      final c = await _category(t, id);
      if (c.isSystem) {
        throw ValidationException(
            'Built-in categories (Self Transfer, Credit Bill Repayment) cannot be deleted.');
      }
      final n = Sqflite.firstIntValue(await t.rawQuery(
              'SELECT COUNT(*) FROM transactions WHERE category_id=?', [id])) ??
          0;
      if (n > 0) {
        throw ValidationException(
            'This category is used by $n existing transaction(s). Deleting it would affect account balances. Edit those transactions first.');
      }
      await t.delete('categories', where: 'id=?', whereArgs: [id]);
    });
  }

  // ───────────────────────── transactions ─────────────────────────

  /// Returns transactions matching [f], newest first.
  Future<List<TxnRecord>> queryTransactions(TxnFilter f) async {
    final d = await db;
    final w = <String>[]; // WHERE fragments, joined with AND
    final args = <Object?>[];
    if (f.text.trim().isNotEmpty) {
      w.add('(t.description LIKE ? OR c.name LIKE ? OR a.name LIKE ?)');
      final p = '%${f.text.trim()}%';
      args.addAll([p, p, p]);
    }
    if (f.accountId != null) {
      w.add('t.account_id=?');
      args.add(f.accountId);
    }
    if (f.categoryId != null) {
      w.add('t.category_id=?');
      args.add(f.categoryId);
    }
    if (f.status != null) {
      w.add('t.status=?');
      args.add(f.status);
    }
    if (f.direction == 'credit') w.add('t.amount>0');
    if (f.direction == 'debit') w.add('t.amount<0');
    if (f.from != null) {
      w.add('t.date_time>=?');
      args.add(DateTime(f.from!.year, f.from!.month, f.from!.day)
          .millisecondsSinceEpoch);
    }
    if (f.to != null) {
      // include the whole "to" day
      w.add('t.date_time<=?');
      args.add(DateTime(f.to!.year, f.to!.month, f.to!.day, 23, 59, 59, 999)
          .millisecondsSinceEpoch);
    }
    if (f.minAmount != null) {
      w.add('ABS(t.amount)>=?');
      args.add(f.minAmount);
    }
    if (f.maxAmount != null) {
      w.add('ABS(t.amount)<=?');
      args.add(f.maxAmount);
    }
    final rows = await d.rawQuery(
        'SELECT t.*, a.name AS account_name, a.color AS account_color, '
        'c.name AS category_name, c.type AS category_type, c.icon AS category_icon, '
        // name of the other account of a self transfer (same group, other row)
        '(SELECT a2.name FROM transactions t2 JOIN accounts a2 ON a2.id=t2.account_id '
        ' WHERE t2.transfer_group=t.transfer_group AND t2.id<>t.id LIMIT 1) AS other_name '
        'FROM transactions t '
        'JOIN accounts a ON a.id=t.account_id '
        'JOIN categories c ON c.id=t.category_id '
        '${w.isEmpty ? '' : 'WHERE ${w.join(' AND ')}'} '
        'ORDER BY t.date_time DESC, t.id DESC',
        args);
    return rows.map(TxnRecord.fromMap).toList();
  }

  /// Loads a transaction as form input. For a self transfer both legs are
  /// read so the form can show the "from" and "to" account.
  Future<TxnInput> loadInput(int id) async {
    final d = await db;
    final row =
        (await d.query('transactions', where: 'id=?', whereArgs: [id])).first;
    final group = row['transfer_group'] as String?;
    var accountId = row['account_id'] as int;
    int? toId;
    if (group != null) {
      final rows = await d
          .query('transactions', where: 'transfer_group=?', whereArgs: [group]);
      for (final r in rows) {
        if ((r['amount'] as int) < 0) {
          accountId = r['account_id'] as int; // debit leg = "from"
        } else {
          toId = r['account_id'] as int; // credit leg = "to"
        }
      }
    }
    return TxnInput(
      categoryId: row['category_id'] as int,
      description: row['description'] as String,
      dateTime: DateTime.fromMillisecondsSinceEpoch(row['date_time'] as int),
      amountPaise: (row['amount'] as int).abs(),
      accountId: accountId,
      toAccountId: toId,
      status: row['status'] as String,
    );
  }

  /// Field-level validation shared by add and update.
  void _checkInput(TxnInput i, Category cat) {
    if (i.description.trim().isEmpty) {
      throw ValidationException('Description is required.');
    }
    if (i.amountPaise <= 0) {
      throw ValidationException('Value must be greater than zero.');
    }
    if (cat.isTwoLeg) {
      if (i.toAccountId == null) {
        throw ValidationException('Select the "to" account.');
      }
      if (i.toAccountId == i.accountId) {
        throw ValidationException('"From" and "To" accounts must be different.');
      }
    }
  }

  /// Adds a transaction. A self transfer / credit bill repayment creates TWO
  /// rows sharing one `transfer_group`: a debit on the "from" account and a
  /// credit on the "to" account.
  /// Returns the id of the (first) inserted row.
  Future<int> addTransaction(TxnInput i) async {
    final d = await db;
    return d.transaction((t) async {
      var firstId = 0;
      final cat = await _category(t, i.categoryId);
      _checkInput(i, cat);
      if (cat.isRepayment) await _checkRepayment(t, i);
      final before = await _availableMap(t);
      final now = DateTime.now().millisecondsSinceEpoch;
      final sched = i.status == 'scheduled';

      // Builds one row. Scheduled rows remember their original plan.
      Map<String, Object?> row(int acc, int amt, String? group) => {
            'account_id': acc,
            'category_id': i.categoryId,
            'description': i.description.trim(),
            'date_time': i.dateTime.millisecondsSinceEpoch,
            'amount': amt,
            'status': i.status,
            'transfer_group': group,
            'sched_date_time': sched ? i.dateTime.millisecondsSinceEpoch : null,
            'sched_description': sched ? i.description.trim() : null,
            'sched_amount': sched ? amt : null,
            'completed_at': sched ? null : now,
            'created_at': now,
            'updated_at': now,
          };

      if (cat.isTwoLeg) {
        final g = '${now}_${Random().nextInt(1 << 30)}';
        firstId = await t.insert('transactions', row(i.accountId, -i.amountPaise, g));
        await t.insert('transactions', row(i.toAccountId!, i.amountPaise, g));
      } else {
        // sign comes from the category type: credit adds, deduct subtracts
        final amt = cat.isCredit ? i.amountPaise : -i.amountPaise;
        firstId = await t.insert('transactions', row(i.accountId, amt, null));
      }
      // scheduled entries may push the AVAILABLE balance below zero
      await _validate(t, before: before, skipAvailable: sched);
      return firstId;
    });
  }

  /// Updates a transaction (both legs for a self transfer).
  ///
  /// Scheduled -> actual keeps the original scheduled date / description /
  /// value in the `sched_*` columns. While it stays scheduled, the `sched_*`
  /// columns follow the edits (the plan itself changed).
  Future<void> updateTransaction(int id, TxnInput i) async {
    final d = await db;
    await d.transaction((t) async {
      final rows = await t.query('transactions', where: 'id=?', whereArgs: [id]);
      if (rows.isEmpty) throw ValidationException('Transaction no longer exists.');
      final old = rows.first;
      final group = old['transfer_group'] as String?;
      final cat = await _category(t, i.categoryId);
      _checkInput(i, cat);
      if ((group != null) != cat.isTwoLeg) {
        throw ValidationException(
            'A transaction cannot be switched to/from Self Transfer. Delete it and add a new one.');
      }
      final wasSched = old['status'] == 'scheduled';
      if (!wasSched && i.status == 'scheduled') {
        throw ValidationException(
            'A completed (actual) transaction cannot be moved back to scheduled.');
      }
      final becameActual = wasSched && i.status == 'actual';
      final stillSched = i.status == 'scheduled';
      if (cat.isRepayment) await _checkRepayment(t, i);
      final before = await _availableMap(t);
      final now = DateTime.now().millisecondsSinceEpoch;

      Map<String, Object?> vals(int acc, int amt) => {
            'account_id': acc,
            'category_id': i.categoryId,
            'description': i.description.trim(),
            'date_time': i.dateTime.millisecondsSinceEpoch,
            'amount': amt,
            'status': i.status,
            'updated_at': now,
            if (stillSched) ...{
              'sched_date_time': i.dateTime.millisecondsSinceEpoch,
              'sched_description': i.description.trim(),
              'sched_amount': amt,
            },
            if (becameActual) 'completed_at': now,
          };

      if (group != null) {
        // update both legs in place: debit leg -> from, credit leg -> to
        final legs = await t
            .query('transactions', where: 'transfer_group=?', whereArgs: [group]);
        for (final r in legs) {
          final isDebit = (r['amount'] as int) < 0;
          await t.update(
              'transactions',
              vals(isDebit ? i.accountId : i.toAccountId!,
                  isDebit ? -i.amountPaise : i.amountPaise),
              where: 'id=?',
              whereArgs: [r['id']]);
        }
      } else {
        final amt = cat.isCredit ? i.amountPaise : -i.amountPaise;
        await t.update('transactions', vals(i.accountId, amt),
            where: 'id=?', whereArgs: [id]);
      }
      // editing a purely scheduled entry may push AVAILABLE below zero
      await _validate(t,
          before: before, skipAvailable: wasSched && stillSched);
    });
  }

  /// Deletes a transaction (both legs of a self transfer).
  Future<void> deleteTransaction(int id) async {
    final d = await db;
    await d.transaction((t) async {
      final rows = await t.query('transactions', where: 'id=?', whereArgs: [id]);
      if (rows.isEmpty) return;
      final group = rows.first['transfer_group'] as String?;
      final wasScheduled = rows.first['status'] == 'scheduled';
      final before = await _availableMap(t);
      await _unlinkTxns(t, group != null ? 'transfer_group=?' : 'id=?',
          [group ?? id]);
      if (group != null) {
        await t.delete('transactions',
            where: 'transfer_group=?', whereArgs: [group]);
      } else {
        await t.delete('transactions', where: 'id=?', whereArgs: [id]);
      }
      await _validate(t, before: before, skipAvailable: wasScheduled);
    });
  }

  // ───────────────────────── todos ─────────────────────────

  Future<List<TodoGroup>> getGroups() async =>
      (await (await db).query('todo_groups', orderBy: 'LOWER(name)'))
          .map((m) => TodoGroup(id: m['id'] as int, name: m['name'] as String))
          .toList();

  /// Creates (id == null) or renames a todo group. Returns its id.
  Future<int> saveGroup(String name, {int? id}) async {
    final d = await db;
    final n = name.trim();
    if (n.isEmpty) throw ValidationException('Group name is required.');
    final dup = await d.query('todo_groups',
        where: id == null ? 'LOWER(name)=?' : 'LOWER(name)=? AND id<>$id',
        whereArgs: [n.toLowerCase()]);
    if (dup.isNotEmpty) throw ValidationException('Group "$n" already exists.');
    if (id == null) return d.insert('todo_groups', {'name': n});
    await d.update('todo_groups', {'name': n}, where: 'id=?', whereArgs: [id]);
    return id;
  }

  /// Deletes a group; its todos are kept but become ungrouped.
  Future<void> deleteGroup(int id) async {
    final d = await db;
    await d.transaction((t) async {
      await t.update('todos', {'group_id': null},
          where: 'group_id=?', whereArgs: [id]);
      await t.delete('todo_groups', where: 'id=?', whereArgs: [id]);
    });
  }

  /// Pending todos first (by due date, undated last), then completed ones.
  Future<List<Todo>> getTodos() async => (await (await db).rawQuery(
          'SELECT t.*, g.name AS group_name FROM todos t '
          'LEFT JOIN todo_groups g ON g.id=t.group_id '
          'ORDER BY t.is_done, CASE WHEN t.due_at IS NULL THEN 1 ELSE 0 END, t.due_at, t.id'))
      .map(Todo.fromMap)
      .toList();

  Future<int> saveTodo(Todo t) async {
    final d = await db;
    if (t.title.trim().isEmpty) throw ValidationException('Title is required.');
    if (t.id == null) {
      final m = t.toMap();
      m['created_at'] = DateTime.now().millisecondsSinceEpoch;
      return d.insert('todos', m);
    }
    await d.update('todos', t.toMap(), where: 'id=?', whereArgs: [t.id]);
    return t.id!;
  }

  Future<void> setTodoDone(int id, bool done) async => (await db).update(
      'todos',
      {
        'is_done': done ? 1 : 0,
        'completed_at': done ? DateTime.now().millisecondsSinceEpoch : null
      },
      where: 'id=?',
      whereArgs: [id]);

  Future<void> deleteTodo(int id) async =>
      (await db).delete('todos', where: 'id=?', whereArgs: [id]);
}
