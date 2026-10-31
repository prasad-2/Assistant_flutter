// "How was this value calculated?" popup of an account card.
//
// Opened by tapping Actual, Scheduled in, Scheduled out, Summary or Available
// on a card. It shows the calculation line by line and, below it, the
// transactions that are responsible for the number (grouped per account when
// child accounts contribute).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/app_database.dart';
import '../models/models.dart';
import '../providers/app_state.dart';
import '../utils/format.dart';
import '../utils/icons.dart';
import 'account_avatar.dart';
import 'common.dart';

/// Which card value was tapped.
enum BreakdownKind { actual, scheduledIn, scheduledOut, summary, available, totalSpend }

Future<void> showAccountBreakdown(
    BuildContext context, AccountSummary summary, BreakdownKind kind,
    {required bool hidden}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _BreakdownSheet(summary: summary, kind: kind, hidden: hidden),
  );
}

/// Transactions of ONE account split by role.
class _Group {
  final Account account;
  final int depth;
  final List<TxnRecord> actual = []; // status actual (credits + debits)
  final List<TxnRecord> schedIn = []; // scheduled credits
  final List<TxnRecord> schedOut = []; // scheduled debits
  _Group(this.account, this.depth);

  int get actualNet => actual.fold(0, (s, t) => s + t.amount);
  int get actualIn => actual.where((t) => t.amount > 0).fold(0, (s, t) => s + t.amount);
  int get actualOut => actual.where((t) => t.amount < 0).fold(0, (s, t) => s - t.amount);
  int get inTotal => schedIn.fold(0, (s, t) => s + t.amount);
  int get outTotal => schedOut.fold(0, (s, t) => s - t.amount); // positive
}

class _BreakdownSheet extends StatefulWidget {
  final AccountSummary summary;
  final BreakdownKind kind;
  final bool hidden;
  const _BreakdownSheet(
      {required this.summary, required this.kind, required this.hidden});
  @override
  State<_BreakdownSheet> createState() => _BreakdownSheetState();
}

class _BreakdownSheetState extends State<_BreakdownSheet> {
  List<_Group>? _groups; // [0] = this account, then its descendants

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Loads the transactions of this account and of all its child accounts
  /// (child balances are part of the parent's ACTUAL value).
  Future<void> _load() async {
    final st = context.read<AppState>();
    final me = widget.summary.account;
    final below = descendantsOf(me.id!, st.accounts);
    final order = <_Group>[_Group(me, 0)];
    // tree order of the summaries gives a sensible display order + depth
    final myDepth =
        st.summaries.firstWhere((x) => x.account.id == me.id).depth;
    for (final x in st.summaries) {
      if (below.contains(x.account.id)) {
        order.add(_Group(x.account, x.depth - myDepth));
      }
    }
    for (final g in order) {
      final list = await AppDatabase.instance
          .queryTransactions(TxnFilter(accountId: g.account.id));
      for (final t in list) {
        if (t.isScheduled) {
          (t.amount > 0 ? g.schedIn : g.schedOut).add(t);
        } else {
          g.actual.add(t);
        }
      }
    }
    if (mounted) setState(() => _groups = order);
  }

  String _money(int v) => formatInr(v, hidden: widget.hidden);

  /// green for positive, red for negative, neutral for zero / hidden
  Color? _sign(int v) {
    if (widget.hidden || v == 0) return null;
    return v > 0 ? creditColor(context) : debitColor(context);
  }

  // ───────────── small building blocks ─────────────

  /// One calculation line: label on the left, amount on the right.
  Widget _line(String label, int value,
      {String op = '', bool total = false, int indent = 0, Color? color, String? note}) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(indent * 14.0, 4, 0, 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
            width: 22,
            child: Text(op,
                style: TextStyle(
                    fontWeight: FontWeight.w700, color: cs.onSurfaceVariant))),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: TextStyle(
                    fontWeight: total ? FontWeight.w700 : FontWeight.w400)),
            if (note != null)
              Text(note,
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          ]),
        ),
        const SizedBox(width: 8),
        Text(_money(value),
            style: TextStyle(
                fontSize: total ? 18 : 15,
                fontWeight: total ? FontWeight.w700 : FontWeight.w500,
                color: color ?? _sign(value))),
      ]),
    );
  }

  Widget _heading(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 14, 0, 4),
        child: Text(t,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
      );

  /// One responsible transaction (amount coloured, no +/- prefix).
  Widget _tile(TxnRecord t) {
    final credit = t.amount > 0;
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Icon(categoryIconFor(t.categoryIcon), size: 20),
      title: Text(t.description, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
          '${fmtDateTime.format(t.dateTime)}  •  ${t.categoryName}'
          '${t.isTransfer ? '  •  ${credit ? 'from' : 'to'} ${t.otherAccountName ?? ''}' : ''}',
          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
      trailing: Text(_money(t.amount.abs()),
          style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: widget.hidden ? null : (credit ? creditColor(context) : debitColor(context)))),
    );
  }

  /// Collapsible list of transactions with a title and a total on the right.
  Widget _expansion(String title, String sub, int total, List<TxnRecord> txns,
      {bool open = false, int indent = 0, bool signed = true, Color? color}) {
    return Padding(
      padding: EdgeInsets.only(left: indent * 14.0),
      child: Card(
        margin: const EdgeInsets.only(bottom: 6),
        elevation: 0,
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        child: ExpansionTile(
          initiallyExpanded: open && txns.isNotEmpty,
          shape: const Border(),
          collapsedShape: const Border(),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('$sub • ${txns.length} transaction${txns.length == 1 ? '' : 's'}',
              style: const TextStyle(fontSize: 11)),
          trailing: Text(_money(total),
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: color ?? (signed ? _sign(total) : null))),
          children: txns.isEmpty
              ? [const Padding(padding: EdgeInsets.all(12), child: Text('No transactions'))]
              : [for (final t in txns) _tile(t)],
        ),
      ),
    );
  }

  // ───────────── the five variants ─────────────

  /// ACTUAL = own actual ledger + every child account's ledger (+ credit limit).
  List<Widget> _actual(List<_Group> g) {
    final a = widget.summary.account;
    final own = g.first;
    final kids = g.skip(1).toList();
    return [
      _heading('Calculation'),
      _line('Credits received on this account', own.actualIn, op: '+', color: creditColor(context)),
      _line('Debits paid from this account', own.actualOut, op: '−', color: debitColor(context)),
      _line('Net of this account', own.actualNet, op: '=', note: 'actual transactions only'),
      for (final k in kids)
        _line('${k.account.name} (child account)', k.actualNet,
            op: '+', indent: k.depth - 1, note: 'its own actual transactions'),
      if (a.isCredit)
        _line('Credit limit', a.creditLimit, op: '+', color: null,
            note: 'credit accounts start with their limit'),
      const Divider(),
      _line('Actual', widget.summary.actual, op: '=', total: true),
      _heading('Responsible transactions'),
      _expansion(own.account.name, 'this account', own.actualNet, own.actual, open: true),
      for (final k in kids)
        if (k.actual.isNotEmpty)
          _expansion(k.account.name, 'child account', k.actualNet, k.actual, indent: k.depth),
    ];
  }

  /// SCHEDULED IN = scheduled credits of this account.
  List<Widget> _schedIn(_Group own) => [
        _heading('Calculation'),
        _line('Scheduled credits (money to receive)', own.inTotal,
            op: '+', note: '${own.schedIn.length} scheduled transaction(s) of this account'),
        const Divider(),
        _line('Scheduled in', widget.summary.scheduledIn, op: '=', total: true),
        _heading('Responsible transactions'),
        _expansion('Scheduled credits', 'this account', own.inTotal, own.schedIn, open: true),
      ];

  /// SCHEDULED OUT = scheduled debits of this account (shown as a positive number).
  List<Widget> _schedOut(_Group own) => [
        _heading('Calculation'),
        _line('Scheduled debits (money to pay)', own.outTotal,
            op: '+', color: debitColor(context),
            note: '${own.schedOut.length} scheduled transaction(s) of this account'),
        const Divider(),
        _line('Scheduled out', widget.summary.scheduledOut,
            op: '=', total: true, color: debitColor(context)),
        _heading('Responsible transactions'),
        _expansion('Scheduled debits', 'this account', own.outTotal, own.schedOut,
            open: true, color: debitColor(context)),
      ];

  /// SUMMARY = actual + scheduled in − scheduled out.
  List<Widget> _summary(List<_Group> g) {
    final s = widget.summary;
    final own = g.first;
    return [
      _heading('Calculation'),
      _line('Actual', s.actual, op: ' ', note: 'own + child accounts' + (s.account.isCredit ? ' + credit limit' : '')),
      _line('Scheduled in', s.scheduledIn, op: '+'),
      _line('Scheduled out', s.scheduledOut, op: '−', color: debitColor(context)),
      const Divider(),
      _line('Summary', s.actual + s.scheduledIn - s.scheduledOut, op: '=', total: true,
          note: 'what the account will hold when everything scheduled is done'),
      _heading('Responsible transactions'),
      _expansion('Actual', 'this account + child accounts',
          g.fold(0, (a, x) => a + x.actualNet), [for (final x in g) ...x.actual]),
      _expansion('Scheduled in', 'this account', own.inTotal, own.schedIn),
      _expansion('Scheduled out', 'this account', own.outTotal, own.schedOut,
          color: debitColor(context)),
    ];
  }

  /// AVAILABLE = own actual ledger − blocked scheduled debits (+ credit limit).
  /// Child accounts are NOT part of it: only this account's own money.
  List<Widget> _available(_Group own) {
    final a = widget.summary.account;
    return [
      _heading('Calculation'),
      _line('Own actual transactions (net)', own.actualNet,
          op: ' ', note: 'child accounts are not included'),
      _line('Blocked by scheduled debits', own.outTotal,
          op: '−', color: debitColor(context),
          note: 'scheduled money to pay is reserved'),
      if (kScheduledCreditsCountInAvailable)
        _line('Scheduled credits', own.inTotal, op: '+'),
      if (a.isCredit)
        _line('Credit limit', a.creditLimit, op: '+', note: 'credit accounts add their limit'),
      const Divider(),
      _line('Available', widget.summary.available, op: '=', total: true),
      if (!kScheduledCreditsCountInAvailable)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
              'Scheduled credits (${_money(own.inTotal)}) are not added until they become actual.',
              style: Theme.of(context).textTheme.bodySmall),
        ),
      _heading('Responsible transactions'),
      _expansion('Actual transactions', 'this account', own.actualNet, own.actual, open: true),
      _expansion('Scheduled debits (blocked)', 'this account', own.outTotal, own.schedOut,
          color: debitColor(context)),
    ];
  }

  /// TOTAL SPEND (credit accounts) = credit limit − ACTUAL value.
  /// Scheduled transactions are deliberately ignored.
  List<Widget> _totalSpend(List<_Group> g) {
    final s = widget.summary;
    final a = s.account;
    final spend = a.creditLimit > s.actual ? a.creditLimit - s.actual : 0;
    final outAll = g.fold<int>(0, (x, e) => x + e.actualOut);
    final inAll = g.fold<int>(0, (x, e) => x + e.actualIn);
    return [
      _heading('Calculation'),
      _line('Credit limit', a.creditLimit, op: ' '),
      _line('Actual value', s.actual,
          op: '−', note: 'actual transactions (this + child accounts) + credit limit'),
      const Divider(),
      _line('Total spend', spend, op: '=', total: true, color: debitColor(context)),
      _heading('Same amount from the transactions'),
      _line('Debits (money spent)', outAll, op: ' ', color: debitColor(context)),
      _line('Credits (repayments / refunds)', inAll, op: '−', color: creditColor(context)),
      const Divider(),
      _line('Spent, net', outAll - inAll, op: '=', total: true,
          color: outAll - inAll > 0 ? debitColor(context) : null,
          note: 'scheduled transactions are not counted'),
      _heading('Responsible transactions'),
      for (final x in g)
        if (x.actual.isNotEmpty || x.depth == 0)
          _expansion(x.account.name, x.depth == 0 ? 'this account' : 'child account',
              x.actualNet, x.actual, open: x.depth == 0, indent: x.depth),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.summary;
    final a = s.account;
    final (title, value) = switch (widget.kind) {
      BreakdownKind.totalSpend => (
          'Total spend',
          a.creditLimit > s.actual ? a.creditLimit - s.actual : 0
        ),
      BreakdownKind.actual => ('Actual', s.actual),
      BreakdownKind.scheduledIn => ('Scheduled in', s.scheduledIn),
      BreakdownKind.scheduledOut => ('Scheduled out', s.scheduledOut),
      BreakdownKind.summary => ('Summary', s.actual + s.scheduledIn - s.scheduledOut),
      BreakdownKind.available => ('Available', s.available),
    };
    final cs = Theme.of(context).colorScheme;
    final groups = _groups;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .8,
      maxChildSize: .95,
      builder: (context, scroll) => Column(children: [
        // header: account + the value being explained
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Row(children: [
            AccountAvatar(iconKey: a.iconKey, blob: a.iconBlob, size: 36),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(a.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                Text('How "$title" is calculated',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ]),
            ),
            Text(_money(value),
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: (widget.kind == BreakdownKind.scheduledOut ||
                            widget.kind == BreakdownKind.totalSpend)
                        ? (widget.hidden || value == 0 ? null : debitColor(context))
                        : _sign(value))),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: groups == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  children: switch (widget.kind) {
                    BreakdownKind.actual => _actual(groups),
                    BreakdownKind.scheduledIn => _schedIn(groups.first),
                    BreakdownKind.scheduledOut => _schedOut(groups.first),
                    BreakdownKind.summary => _summary(groups),
                    BreakdownKind.available => _available(groups.first),
                    BreakdownKind.totalSpend => _totalSpend(groups),
                  },
                ),
        ),
      ]),
    );
  }
}
