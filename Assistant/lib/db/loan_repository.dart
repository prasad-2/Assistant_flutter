// All database access for loan management (loans + EMI schedule).
//
// Money is in paise. Creating a bank transaction for an EMI goes through
// AppDatabase.addTransaction so the normal balance validation applies.
import 'package:sqflite/sqflite.dart';

import '../models/loan_models.dart';
import '../models/models.dart';
import '../utils/loan_math.dart';
import 'app_database.dart';

class LoanRepository {
  LoanRepository._();
  static final LoanRepository instance = LoanRepository._();

  Future<Database> get _db => AppDatabase.instance.db;

  /// All loans with their EMIs and calculated summary (active first).
  Future<List<LoanSummary>> summaries() async {
    final d = await _db;
    final loans = (await d.query('loans', orderBy: "status, LOWER(name)"))
        .map(Loan.fromMap)
        .toList();
    final emis = (await d.query('loan_emis', orderBy: 'loan_id, no'))
        .map(LoanEmi.fromMap)
        .toList();
    final byLoan = <int, List<LoanEmi>>{};
    for (final e in emis) {
      byLoan.putIfAbsent(e.loanId, () => []).add(e);
    }
    return [
      for (final l in loans) LoanSummary.build(l, byLoan[l.id] ?? const [])
    ];
  }

  /// Validates and inserts / updates a loan. Returns its id.
  Future<int> saveLoan(Loan l) async {
    final d = await _db;
    if (l.name.trim().isEmpty) throw ValidationException('Loan name is required.');
    if (l.principal <= 0) throw ValidationException('Loan value must be above 0.');
    if (l.rate < 0 || l.rate > 100) {
      throw ValidationException('Interest must be between 0 and 100 %.');
    }
    if (l.tenureValue <= 0) throw ValidationException('Tenure must be above 0.');
    if (l.freqValue <= 0) throw ValidationException('EMI frequency must be above 0.');
    if (l.foreclosePct < 0 || l.foreclosePct > 100 ||
        l.penaltyPct < 0 || l.penaltyPct > 100) {
      throw ValidationException('Charges must be between 0 and 100 %.');
    }
    final dup = await d.query('loans',
        where: l.id == null ? 'LOWER(name)=?' : 'LOWER(name)=? AND id<>${l.id}',
        whereArgs: [l.name.trim().toLowerCase()]);
    if (dup.isNotEmpty) {
      throw ValidationException('A loan named "${l.name.trim()}" already exists.');
    }
    if (l.id == null) {
      final m = l.toMap();
      m['created_at'] = DateTime.now().millisecondsSinceEpoch;
      return d.insert('loans', m);
    }
    await d.update('loans', l.toMap(), where: 'id=?', whereArgs: [l.id]);
    return l.id!;
  }

  /// Deletes the loan and its EMI entries (linked bank transactions stay).
  Future<void> deleteLoan(int id) async {
    final d = await _db;
    await d.transaction((t) async {
      await t.delete('loan_emis', where: 'loan_id=?', whereArgs: [id]);
      await t.delete('loans', where: 'id=?', whereArgs: [id]);
    });
  }

  Future<void> setEmiAmount(int loanId, int paise) async => (await _db)
      .update('loans', {'emi_amount': paise}, where: 'id=?', whereArgs: [loanId]);

  /// Replaces ALL EMI entries of the loan with a freshly generated schedule
  /// (tenure, frequency, start date, rate and the saved EMI amount).
  Future<void> generateSchedule(Loan loan) async {
    if (loan.emiAmount <= 0) {
      throw ValidationException('Calculate the EMI first.');
    }
    final rows = buildSchedule(
      principal: loan.principal,
      annualPct: loan.rate,
      n: loan.installments,
      emi: loan.emiAmount,
      start: loan.startDate,
      freqValue: loan.freqValue,
      freqUnit: loan.freqUnit,
    );
    final d = await _db;
    await d.transaction((t) async {
      await t.delete('loan_emis', where: 'loan_id=?', whereArgs: [loan.id]);
      for (final r in rows) {
        await t.insert('loan_emis', {
          'loan_id': loan.id,
          'no': r.no,
          'due_date': r.due.millisecondsSinceEpoch,
          'emi': r.emi,
          'principal_part': r.principalPart,
          'interest_part': r.interestPart,
          'status': 'pending',
        });
      }
      await t.update('loans', {'status': 'active'},
          where: 'id=?', whereArgs: [loan.id]);
    });
  }

  /// Edits one EMI: due date and amount. The interest part is kept and the
  /// principal part becomes (amount - interest).
  Future<void> updateEmi(LoanEmi e, DateTime due, int emi) async {
    if (emi <= 0) throw ValidationException('EMI amount must be above 0.');
    final principal = emi > e.interestPart ? emi - e.interestPart : 0;
    await (await _db).update(
        'loan_emis',
        {
          'due_date': due.millisecondsSinceEpoch,
          'emi': emi,
          'principal_part': principal,
        },
        where: 'id=?',
        whereArgs: [e.id]);
  }

  Future<void> markPaid(int emiId, DateTime paidDate, int penalty) async =>
      (await _db).update(
          'loan_emis',
          {
            'status': 'paid',
            'paid_date': paidDate.millisecondsSinceEpoch,
            'penalty': penalty < 0 ? 0 : penalty,
          },
          where: 'id=?',
          whereArgs: [emiId]);

  Future<void> markUnpaid(int emiId) async => (await _db).update(
      'loan_emis', {'status': 'pending', 'paid_date': null, 'penalty': 0},
      where: 'id=?', whereArgs: [emiId]);

  /// Foreclose: the loan is closed and all unpaid EMIs are cancelled.
  Future<void> foreclose(int loanId) async {
    final d = await _db;
    await d.transaction((t) async {
      await t.update('loan_emis', {'status': 'cancelled'},
          where: "loan_id=? AND status='pending'", whereArgs: [loanId]);
      await t.update('loans', {'status': 'closed'},
          where: 'id=?', whereArgs: [loanId]);
    });
  }

  /// Creates ONE bank transaction for an EMI (category "Emi Payment", debit)
  /// and links it. For an ACTUAL payment the EMI is also marked as paid.
  Future<void> createBankTransaction({
    required LoanEmi emi,
    required int accountId,
    required String status, // actual | scheduled
    required String description,
  }) async {
    final cat = await AppDatabase.instance
        .categoryIdByName('Emi Payment', 'debit', 'account_balance');
    final actual = status == 'actual';
    final id = await AppDatabase.instance.addTransaction(TxnInput(
      categoryId: cat,
      description: description,
      // scheduled: on the EMI date; actual: paid now
      dateTime: actual ? DateTime.now() : emi.dueDate,
      amountPaise: emi.emi,
      accountId: accountId,
      status: status,
    ));
    final d = await _db;
    await d.update('loan_emis', {'txn_id': id},
        where: 'id=?', whereArgs: [emi.id]);
    if (actual && !emi.isPaid) await markPaid(emi.id, DateTime.now(), 0);
  }
}
