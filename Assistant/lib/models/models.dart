// Plain data classes shared by the database, state and UI layers.
//
// Conventions
//  * All money values are integers in PAISE (1 rupee = 100 paise) to avoid
//    floating point errors.
//  * Transaction amounts are SIGNED: credit = positive, debit = negative.
import 'dart:typed_data';

/// Thrown by the database layer when an operation would break a business
/// rule (e.g. negative balance). The message is shown to the user as is.
class ValidationException implements Exception {
  final String message;
  ValidationException(this.message);
  @override
  String toString() => message;
}

/// A bank account (real or virtual). Accounts can be nested through [parentId].
class Account {
  final int? id;
  final String name; // bank / account name
  final String owner;
  final int color; // ARGB int, alpha = transparency chosen by the user
  final int? parentId; // parent account (virtual accounts live under a real one)
  final bool isCredit; // credit-card style account
  final int creditLimit; // paise, only meaningful when [isCredit]
  final bool isRegular; // shown on the home screen
  final String notes; // free text notes about the account
  final String iconKey; // `bank:<key>` | `icon:<key>`; see utils/icons.dart
  final Uint8List? iconBlob; // optional user-uploaded icon (PNG bytes)

  const Account({
    this.id,
    required this.name,
    required this.owner,
    required this.color,
    this.parentId,
    this.isCredit = false,
    this.creditLimit = 0,
    this.isRegular = false,
    this.notes = '',
    this.iconKey = 'icon:bank',
    this.iconBlob,
  });

  factory Account.fromMap(Map<String, Object?> m) => Account(
        id: m['id'] as int,
        name: m['name'] as String,
        owner: m['owner'] as String,
        color: m['color'] as int,
        parentId: m['parent_id'] as int?,
        isCredit: (m['is_credit'] as int) == 1,
        creditLimit: m['credit_limit'] as int,
        isRegular: (m['is_regular'] as int) == 1,
        notes: (m['notes'] as String?) ?? '',
        iconKey: (m['icon_key'] as String?) ?? 'icon:bank',
        iconBlob: m['icon_blob'] as Uint8List?,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'name': name.trim(),
        'owner': owner.trim(),
        'color': color,
        'parent_id': parentId,
        'is_credit': isCredit ? 1 : 0,
        'credit_limit': isCredit ? creditLimit : 0,
        'is_regular': isRegular ? 1 : 0,
        'notes': notes.trim(),
        'icon_key': iconKey,
        'icon_blob': iconBlob,
      };
}

/// Transaction category (master data maintained in Settings).
class Category {
  final int? id;
  final String name;

  /// `credit` (adds money), `debit` (deducts money), `transfer` (built-in
  /// Self Transfer) or `repayment` (built-in Credit Bill Repayment: pays a
  /// credit account from a normal account).
  final String type;
  final String icon; // key into kCategoryIcons

  const Category(
      {this.id, required this.name, required this.type, this.icon = 'category'});

  bool get isTransfer => type == 'transfer';
  bool get isRepayment => type == 'repayment';

  /// Categories that create TWO linked entries (a debit and a credit).
  bool get isTwoLeg => isTransfer || isRepayment;

  /// Built-in categories that the user cannot edit or delete.
  bool get isSystem => isTwoLeg;

  bool get isCredit => type == 'credit';
  String get typeLabel => isTransfer
      ? 'Self transfer'
      : isRepayment
          ? 'Credit bill repayment'
          : (isCredit ? 'Credit' : 'Deduct');

  factory Category.fromMap(Map<String, Object?> m) => Category(
        id: m['id'] as int,
        name: m['name'] as String,
        type: m['type'] as String,
        icon: (m['icon'] as String?) ?? 'category',
      );
}

/// Account + its calculated balances, ready to be displayed.
class AccountSummary {
  final Account account;
  final int depth; // nesting level (0 = top level)
  final String? parentName;
  final bool hasChildren;

  /// Own ledger + all nested child ledgers (+ credit limit for credit accounts).
  final int actual;

  /// Own ledger after blocking scheduled debits (the "funds block" concept).
  final int available;

  /// Signed sum of scheduled transactions of this account only.
  final int scheduledNet;

  const AccountSummary({
    required this.account,
    required this.depth,
    required this.parentName,
    required this.hasChildren,
    required this.actual,
    required this.available,
    required this.scheduledNet,
  });
}

/// One transaction row joined with account and category information.
class TxnRecord {
  final int id;
  final int accountId;
  final String accountName;
  final int accountColor;
  final int categoryId;
  final String categoryName;
  final String categoryType;
  final String categoryIcon;
  final String description;
  final DateTime dateTime;
  final int amount; // signed paise
  final String status; // actual | scheduled
  final String? transferGroup; // shared id of the two legs of a self transfer
  final String? otherAccountName; // counterpart account of a self transfer

  // Original "scheduled" information, kept after a scheduled transaction is
  // completed so it can be used for later analysis.
  final DateTime? schedDateTime;
  final String? schedDescription;
  final int? schedAmount;
  final DateTime? completedAt;

  const TxnRecord({
    required this.id,
    required this.accountId,
    required this.accountName,
    required this.accountColor,
    required this.categoryId,
    required this.categoryName,
    required this.categoryType,
    required this.categoryIcon,
    required this.description,
    required this.dateTime,
    required this.amount,
    required this.status,
    required this.transferGroup,
    required this.otherAccountName,
    required this.schedDateTime,
    required this.schedDescription,
    required this.schedAmount,
    required this.completedAt,
  });

  bool get isScheduled => status == 'scheduled';
  bool get isTransfer => transferGroup != null;

  static DateTime? _dt(Object? v) =>
      v == null ? null : DateTime.fromMillisecondsSinceEpoch(v as int);

  factory TxnRecord.fromMap(Map<String, Object?> m) => TxnRecord(
        id: m['id'] as int,
        accountId: m['account_id'] as int,
        accountName: m['account_name'] as String,
        accountColor: m['account_color'] as int,
        categoryId: m['category_id'] as int,
        categoryName: m['category_name'] as String,
        categoryType: m['category_type'] as String,
        categoryIcon: (m['category_icon'] as String?) ?? 'category',
        description: m['description'] as String,
        dateTime: DateTime.fromMillisecondsSinceEpoch(m['date_time'] as int),
        amount: m['amount'] as int,
        status: m['status'] as String,
        transferGroup: m['transfer_group'] as String?,
        otherAccountName: m['other_name'] as String?,
        schedDateTime: _dt(m['sched_date_time']),
        schedDescription: m['sched_description'] as String?,
        schedAmount: m['sched_amount'] as int?,
        completedAt: _dt(m['completed_at']),
      );
}

/// Form input for add / edit transaction. [amountPaise] is always positive;
/// the sign is derived from the category.
class TxnInput {
  final int categoryId;
  final String description;
  final DateTime dateTime;
  final int amountPaise;
  final int accountId; // source account ("from" account for transfers)
  final int? toAccountId; // only for self transfer
  final String status;

  const TxnInput({
    required this.categoryId,
    required this.description,
    required this.dateTime,
    required this.amountPaise,
    required this.accountId,
    this.toAccountId,
    required this.status,
  });
}

/// Filter used by the transaction list. All fields are optional.
class TxnFilter {
  final String text;
  final int? accountId;
  final int? categoryId;
  final String? status; // actual | scheduled
  final String? direction; // credit | debit
  final DateTime? from;
  final DateTime? to;
  final int? minAmount; // paise
  final int? maxAmount;

  const TxnFilter({
    this.text = '',
    this.accountId,
    this.categoryId,
    this.status,
    this.direction,
    this.from,
    this.to,
    this.minAmount,
    this.maxAmount,
  });

  /// True when at least one field restricts the result.
  bool get isActive =>
      text.isNotEmpty ||
      accountId != null ||
      categoryId != null ||
      status != null ||
      direction != null ||
      from != null ||
      to != null ||
      minAmount != null ||
      maxAmount != null;
}

class TodoGroup {
  final int? id;
  final String name;
  const TodoGroup({this.id, required this.name});
}

/// A todo item with optional due date and alarm-style reminder.
class Todo {
  final int? id;
  final String title;
  final String notes;
  final int? groupId;
  final String? groupName;
  final DateTime? dueAt;
  final bool reminder;
  final int reminderOffsetMin; // minutes before [dueAt]
  final bool isDone;
  final DateTime? completedAt;

  const Todo({
    this.id,
    required this.title,
    this.notes = '',
    this.groupId,
    this.groupName,
    this.dueAt,
    this.reminder = false,
    this.reminderOffsetMin = 0,
    this.isDone = false,
    this.completedAt,
  });

  /// Moment the alarm should ring (null when no reminder is configured).
  DateTime? get reminderAt => (reminder && dueAt != null)
      ? dueAt!.subtract(Duration(minutes: reminderOffsetMin))
      : null;

  bool get isOverdue =>
      !isDone && dueAt != null && dueAt!.isBefore(DateTime.now());

  factory Todo.fromMap(Map<String, Object?> m) => Todo(
        id: m['id'] as int,
        title: m['title'] as String,
        notes: (m['notes'] as String?) ?? '',
        groupId: m['group_id'] as int?,
        groupName: m['group_name'] as String?,
        dueAt: m['due_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(m['due_at'] as int),
        reminder: (m['reminder'] as int) == 1,
        reminderOffsetMin: m['reminder_offset'] as int,
        isDone: (m['is_done'] as int) == 1,
        completedAt: m['completed_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(m['completed_at'] as int),
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'title': title.trim(),
        'notes': notes.trim(),
        'group_id': groupId,
        'due_at': dueAt?.millisecondsSinceEpoch,
        'reminder': reminder ? 1 : 0,
        'reminder_offset': reminderOffsetMin,
        'is_done': isDone ? 1 : 0,
        'completed_at': completedAt?.millisecondsSinceEpoch,
      };
}
