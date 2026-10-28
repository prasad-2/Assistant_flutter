// All database access for debt management (friends, entries, setoff).
import 'package:sqflite/sqflite.dart';

import '../models/debt_models.dart';
import '../models/models.dart';
import 'app_database.dart';

class DebtRepository {
  DebtRepository._();
  static final DebtRepository instance = DebtRepository._();

  Future<Database> get _db => AppDatabase.instance.db;

  /// Every person with their lent / borrowed totals.
  Future<List<DebtPerson>> people() async {
    final rows = await (await _db).rawQuery(
        'SELECT p.id, p.name, '
        "COALESCE(SUM(CASE WHEN e.direction='lent' THEN e.amount END),0) AS lent, "
        "COALESCE(SUM(CASE WHEN e.direction='borrowed' THEN e.amount END),0) AS borrowed, "
        'COUNT(e.id) AS cnt '
        'FROM debt_people p LEFT JOIN debt_entries e ON e.person_id=p.id '
        'GROUP BY p.id ORDER BY LOWER(p.name)');
    return [
      for (final r in rows)
        DebtPerson(
          id: r['id'] as int,
          name: r['name'] as String,
          lent: (r['lent'] as num).toInt(),
          borrowed: (r['borrowed'] as num).toInt(),
          entries: (r['cnt'] as num).toInt(),
        )
    ];
  }

  /// Creates (id == null) or renames a person. Returns the id.
  Future<int> savePerson(String name, {int? id}) async {
    final d = await _db;
    final n = name.trim();
    if (n.isEmpty) throw ValidationException('Name is required.');
    final dup = await d.query('debt_people',
        where: id == null ? 'LOWER(name)=?' : 'LOWER(name)=? AND id<>$id',
        whereArgs: [n.toLowerCase()]);
    if (dup.isNotEmpty) throw ValidationException('"$n" already exists.');
    if (id == null) return d.insert('debt_people', {'name': n});
    await d.update('debt_people', {'name': n}, where: 'id=?', whereArgs: [id]);
    return id;
  }

  /// Deletes a person and all their entries (bank transactions are kept).
  Future<void> deletePerson(int id) async {
    final d = await _db;
    await d.transaction((t) async {
      await t.delete('debt_entries', where: 'person_id=?', whereArgs: [id]);
      await t.delete('debt_people', where: 'id=?', whereArgs: [id]);
    });
  }

  Future<List<DebtEntry>> entries(int personId) async =>
      (await (await _db).query('debt_entries',
              where: 'person_id=?',
              whereArgs: [personId],
              orderBy: 'date_time DESC, id DESC'))
          .map(DebtEntry.fromMap)
          .toList();

  /// Adds or edits an entry. With [link] a bank transaction is created too
  /// (lent = debit "Debt Given", borrowed = credit "Debt Received"). The bank
  /// transaction is created FIRST so a balance error aborts everything.
  Future<int> saveEntry(DebtEntry e,
      {BankLink? link, required String personName}) async {
    if (e.description.trim().isEmpty) {
      throw ValidationException('Description is required.');
    }
    if (e.amount <= 0) throw ValidationException('Value must be above 0.');
    int? txnId = e.txnId;
    if (link != null) {
      txnId = await _createBankTxn(e, link, personName);
    }
    final d = await _db;
    final saved = DebtEntry(
      id: e.id,
      personId: e.personId,
      description: e.description,
      dateTime: e.dateTime,
      amount: e.amount,
      direction: e.direction,
      isSetoff: e.isSetoff,
      txnId: txnId,
    );
    if (e.id == null) {
      final m = saved.toMap();
      m['created_at'] = DateTime.now().millisecondsSinceEpoch;
      return d.insert('debt_entries', m);
    }
    await d.update('debt_entries', saved.toMap(),
        where: 'id=?', whereArgs: [e.id]);
    return e.id!;
  }

  Future<int> _createBankTxn(DebtEntry e, BankLink link, String person) async {
    final debit = e.isBankDebit;
    final cat = debit
        ? await AppDatabase.instance
            .categoryIdByName('Debt Given', 'debit', 'volunteer_activism')
        : await AppDatabase.instance
            .categoryIdByName('Debt Received', 'credit', 'redeem');
    final label = e.isSetoff
        ? (debit ? 'Settlement paid to $person' : 'Settlement received from $person')
        : (debit ? 'Lent to $person' : 'Borrowed from $person');
    return AppDatabase.instance.addTransaction(TxnInput(
      categoryId: cat,
      description: '$label: ${e.description.trim()}',
      dateTime: e.dateTime,
      amountPaise: e.amount,
      accountId: link.accountId,
      status: link.status,
    ));
  }

  Future<void> deleteEntry(int id) async =>
      (await _db).delete('debt_entries', where: 'id=?', whereArgs: [id]);

  /// Links an existing bank transaction (or unlinks with null).
  Future<void> linkTxn(int entryId, int? txnId) async => (await _db).update(
      'debt_entries', {'txn_id': txnId},
      where: 'id=?', whereArgs: [entryId]);

  /// Debt setoff ("settle up"): records an entry opposite to the current
  /// balance so it moves towards zero. [net] is the person's current net.
  Future<void> settle({
    required DebtPerson person,
    required int amount,
    BankLink? link,
  }) async {
    if (person.net == 0) throw ValidationException('Nothing to settle.');
    if (amount <= 0) throw ValidationException('Amount must be above 0.');
    if (amount > person.net.abs()) {
      throw ValidationException(
          'The settlement cannot be more than the amount outstanding.');
    }
    await saveEntry(
      DebtEntry(
        personId: person.id,
        description: 'Settlement',
        dateTime: DateTime.now(),
        amount: amount,
        // they owe me (net>0) -> they pay me -> counts as "borrowed" money in
        direction: person.net > 0 ? 'borrowed' : 'lent',
        isSetoff: true,
      ),
      link: link,
      personName: person.name,
    );
  }
}
