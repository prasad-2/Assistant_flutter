// History of "Distribute balance" operations.
//
// Names are stored as a snapshot next to the account ids, so the history stays
// readable even after an account is renamed or deleted.

/// One target of a distribution.
class DistributionLine {
  final int? toAccountId;
  final String toName;
  final double pct; // percent of the distributed amount
  final int amount; // paise
  final int? txnId; // the self transfer that was created (null once deleted)

  const DistributionLine({
    required this.toAccountId,
    required this.toName,
    required this.pct,
    required this.amount,
    this.txnId,
  });

  factory DistributionLine.fromMap(Map<String, Object?> m) => DistributionLine(
        toAccountId: m['to_account_id'] as int?,
        toName: m['to_name'] as String,
        pct: (m['pct'] as num).toDouble(),
        amount: m['amount'] as int,
        txnId: m['txn_id'] as int?,
      );
}

/// One distribution: a source account, the amount and its targets.
class Distribution {
  final int? id;
  final int? fromAccountId;
  final String fromName;
  final DateTime dateTime; // date-time used for the transactions
  final DateTime? createdAt; // when the distribution was made
  final String status; // actual | scheduled
  final int total; // paise taken from the source
  final List<DistributionLine> lines;

  const Distribution({
    this.id,
    required this.fromAccountId,
    required this.fromName,
    required this.dateTime,
    this.createdAt,
    required this.status,
    required this.total,
    required this.lines,
  });

  bool get isScheduled => status == 'scheduled';
}
