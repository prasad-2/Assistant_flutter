// Debt management (Splitwise-like) data classes.
//
// Balance rule for a person:  net = sum(lent) - sum(borrowed)
//   net > 0  -> the person owes ME
//   net < 0  -> I owe the person
// A "setoff" (settle up) is an ordinary entry flagged `isSetoff` whose
// direction is opposite to the net balance, so the balance moves towards 0.

class DebtEntry {
  final int? id;
  final int personId;
  final String description;
  final DateTime dateTime;
  final int amount; // paise, always positive
  final String direction; // lent (I lent) | borrowed (I borrowed)
  final bool isSetoff;
  final int? txnId; // linked bank transaction

  const DebtEntry({
    this.id,
    required this.personId,
    required this.description,
    required this.dateTime,
    required this.amount,
    required this.direction,
    this.isSetoff = false,
    this.txnId,
  });

  bool get isLent => direction == 'lent';

  /// Money direction in the bank: lending sends money OUT (debit),
  /// borrowing brings money IN (credit).
  bool get isBankDebit => isLent;

  factory DebtEntry.fromMap(Map<String, Object?> m) => DebtEntry(
        id: m['id'] as int,
        personId: m['person_id'] as int,
        description: m['description'] as String,
        dateTime: DateTime.fromMillisecondsSinceEpoch(m['date_time'] as int),
        amount: m['amount'] as int,
        direction: m['direction'] as String,
        isSetoff: (m['is_setoff'] as int) == 1,
        txnId: m['txn_id'] as int?,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'person_id': personId,
        'description': description.trim(),
        'date_time': dateTime.millisecondsSinceEpoch,
        'amount': amount,
        'direction': direction,
        'is_setoff': isSetoff ? 1 : 0,
        'txn_id': txnId,
      };
}

/// A person with totals.
class DebtPerson {
  final int id;
  final String name;
  final int lent; // total I lent
  final int borrowed; // total I borrowed
  final int entries;

  const DebtPerson(
      {required this.id,
      required this.name,
      required this.lent,
      required this.borrowed,
      required this.entries});

  int get net => lent - borrowed;
  bool get owesMe => net > 0;
  bool get iOwe => net < 0;
  bool get settled => net == 0;
}

/// Where to create the linked bank transaction.
class BankLink {
  final int accountId;
  final String status; // actual | scheduled
  const BankLink(this.accountId, this.status);
}
