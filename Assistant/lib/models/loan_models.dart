// Loan management data classes.
//
// A loan is like a bank account (name, colour, icon) but has NO child
// accounts. Its EMI schedule is stored as individual [LoanEmi] rows.
import 'dart:typed_data';

import '../utils/loan_math.dart';

/// Units used for tenure and EMI frequency.
const List<String> kLoanUnits = ['day', 'month', 'year'];

class Loan {
  final int? id;
  final String name;
  final int color; // ARGB
  final String iconKey;
  final Uint8List? iconBlob;
  final int principal; // loan value, paise
  final double rate; // annual interest %
  final int tenureValue;
  final String tenureUnit; // day | month | year
  final DateTime startDate; // first EMI date
  final int freqValue; // EMI every N ...
  final String freqUnit; // ... day | month | year
  final double foreclosePct; // % of outstanding principal charged on foreclosure
  final double penaltyPct; // % of EMI charged when paid late
  final int emiAmount; // paise (0 = not calculated yet)
  final String notes;
  final String status; // active | closed

  const Loan({
    this.id,
    required this.name,
    required this.color,
    this.iconKey = 'icon:bank',
    this.iconBlob,
    required this.principal,
    required this.rate,
    required this.tenureValue,
    required this.tenureUnit,
    required this.startDate,
    required this.freqValue,
    required this.freqUnit,
    this.foreclosePct = 0,
    this.penaltyPct = 0,
    this.emiAmount = 0,
    this.notes = '',
    this.status = 'active',
  });

  bool get isClosed => status == 'closed';

  /// Number of EMIs implied by tenure and frequency.
  int get installments =>
      installmentCount(tenureValue, tenureUnit, freqValue, freqUnit);

  String get tenureText => '$tenureValue $tenureUnit${tenureValue == 1 ? '' : 's'}';
  String get frequencyText =>
      'Every $freqValue $freqUnit${freqValue == 1 ? '' : 's'}';

  Loan copyWith({int? emiAmount, String? status}) => Loan(
        id: id,
        name: name,
        color: color,
        iconKey: iconKey,
        iconBlob: iconBlob,
        principal: principal,
        rate: rate,
        tenureValue: tenureValue,
        tenureUnit: tenureUnit,
        startDate: startDate,
        freqValue: freqValue,
        freqUnit: freqUnit,
        foreclosePct: foreclosePct,
        penaltyPct: penaltyPct,
        emiAmount: emiAmount ?? this.emiAmount,
        notes: notes,
        status: status ?? this.status,
      );

  factory Loan.fromMap(Map<String, Object?> m) => Loan(
        id: m['id'] as int,
        name: m['name'] as String,
        color: m['color'] as int,
        iconKey: (m['icon_key'] as String?) ?? 'icon:bank',
        iconBlob: m['icon_blob'] as Uint8List?,
        principal: m['principal'] as int,
        rate: (m['rate'] as num).toDouble(),
        tenureValue: m['tenure_value'] as int,
        tenureUnit: m['tenure_unit'] as String,
        startDate: DateTime.fromMillisecondsSinceEpoch(m['start_date'] as int),
        freqValue: m['freq_value'] as int,
        freqUnit: m['freq_unit'] as String,
        foreclosePct: (m['foreclose_pct'] as num).toDouble(),
        penaltyPct: (m['penalty_pct'] as num).toDouble(),
        emiAmount: m['emi_amount'] as int,
        notes: (m['notes'] as String?) ?? '',
        status: m['status'] as String,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'name': name.trim(),
        'color': color,
        'icon_key': iconKey,
        'icon_blob': iconBlob,
        'principal': principal,
        'rate': rate,
        'tenure_value': tenureValue,
        'tenure_unit': tenureUnit,
        'start_date': startDate.millisecondsSinceEpoch,
        'freq_value': freqValue,
        'freq_unit': freqUnit,
        'foreclose_pct': foreclosePct,
        'penalty_pct': penaltyPct,
        'emi_amount': emiAmount,
        'notes': notes.trim(),
        'status': status,
      };
}

/// One EMI (instalment) of a loan.
class LoanEmi {
  final int id;
  final int loanId;
  final int no; // 1-based instalment number
  final DateTime dueDate;
  final int emi; // amount to pay, paise
  final int principalPart;
  final int interestPart;
  final String status; // pending | paid | cancelled
  final DateTime? paidDate;
  final int penalty; // late payment penalty actually charged, paise
  final int? txnId; // linked bank transaction (if created)

  const LoanEmi({
    required this.id,
    required this.loanId,
    required this.no,
    required this.dueDate,
    required this.emi,
    required this.principalPart,
    required this.interestPart,
    required this.status,
    this.paidDate,
    this.penalty = 0,
    this.txnId,
  });

  bool get isPaid => status == 'paid';
  bool get isCancelled => status == 'cancelled';
  bool get isOverdue =>
      status == 'pending' && dueDate.isBefore(DateTime.now());

  factory LoanEmi.fromMap(Map<String, Object?> m) => LoanEmi(
        id: m['id'] as int,
        loanId: m['loan_id'] as int,
        no: m['no'] as int,
        dueDate: DateTime.fromMillisecondsSinceEpoch(m['due_date'] as int),
        emi: m['emi'] as int,
        principalPart: m['principal_part'] as int,
        interestPart: m['interest_part'] as int,
        status: m['status'] as String,
        paidDate: m['paid_date'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(m['paid_date'] as int),
        penalty: m['penalty'] as int,
        txnId: m['txn_id'] as int?,
      );
}

/// A loan with everything needed to draw its card.
class LoanSummary {
  final Loan loan;
  final List<LoanEmi> emis;
  final int paidCount;
  final int activeCount; // emis that are not cancelled
  final int paidAmount; // EMIs + penalties paid so far
  final int outstanding; // principal still to be repaid
  final int totalInterest; // interest over the whole schedule
  final LoanEmi? nextDue;
  final int foreclosureAmount; // outstanding + foreclosure charge

  const LoanSummary({
    required this.loan,
    required this.emis,
    required this.paidCount,
    required this.activeCount,
    required this.paidAmount,
    required this.outstanding,
    required this.totalInterest,
    required this.nextDue,
    required this.foreclosureAmount,
  });

  bool get hasSchedule => emis.isNotEmpty;
  double get progress => activeCount == 0 ? 0 : paidCount / activeCount;

  factory LoanSummary.build(Loan loan, List<LoanEmi> emis) {
    final live = emis.where((e) => !e.isCancelled).toList();
    final paid = live.where((e) => e.isPaid).toList();
    final principalPaid = paid.fold<int>(0, (s, e) => s + e.principalPart);
    var outstanding = loan.isClosed ? 0 : loan.principal - principalPaid;
    if (outstanding < 0) outstanding = 0;
    final pending = live.where((e) => !e.isPaid).toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    return LoanSummary(
      loan: loan,
      emis: emis,
      paidCount: paid.length,
      activeCount: live.length,
      paidAmount: paid.fold<int>(0, (s, e) => s + e.emi + e.penalty),
      outstanding: outstanding,
      totalInterest: live.fold<int>(0, (s, e) => s + e.interestPart),
      nextDue: loan.isClosed || pending.isEmpty ? null : pending.first,
      foreclosureAmount:
          outstanding + (outstanding * loan.foreclosePct / 100).round(),
    );
  }
}
