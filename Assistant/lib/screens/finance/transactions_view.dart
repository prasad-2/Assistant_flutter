// Transaction list with filter, detail sheet and edit / delete actions.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../db/app_database.dart';
import '../../models/models.dart';
import '../../providers/app_state.dart';
import '../../utils/format.dart';
import '../../utils/icons.dart';
import '../../widgets/common.dart';
import 'transaction_form.dart';

/// Full page wrapper around [TransactionsView] (used for Scheduled / filters).
class TransactionsPage extends StatelessWidget {
  final String title;
  final TxnFilter initial;
  const TransactionsPage(
      {super.key, required this.title, this.initial = const TxnFilter()});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        floatingActionButton: FloatingActionButton(
          onPressed: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const TransactionFormPage())),
          child: const Icon(Icons.add),
        ),
        body: TransactionsView(initial: initial),
      );
}

/// Filterable list of transactions, newest first. Reloads itself whenever
/// `AppState.financeVersion` changes.
class TransactionsView extends StatefulWidget {
  final TxnFilter initial;
  const TransactionsView({super.key, this.initial = const TxnFilter()});
  @override
  State<TransactionsView> createState() => _TransactionsViewState();
}

class _TransactionsViewState extends State<TransactionsView> {
  late TxnFilter _f = widget.initial;
  List<TxnRecord> _items = [];
  bool _loading = true;
  int _ver = -1;

  /// Runs the current filter against the database.
  Future<void> _load() async {
    final r = await AppDatabase.instance.queryTransactions(_f);
    if (!mounted) return;
    setState(() {
      _items = r;
      _loading = false;
    });
  }

  /// Opens the filter sheet and reloads with the chosen filter.
  Future<void> _openFilter() async {
    final r = await showModalBottomSheet<TxnFilter>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FilterSheet(initial: _f),
    );
    if (r != null) {
      _f = r;
      _load();
    }
  }

  /// Confirms, deletes (both legs for transfers) and refreshes balances.
  Future<void> _delete(TxnRecord t) async {
    final st = context.read<AppState>();
    final ok = await confirmDialog(context,
        title: 'Delete transaction?',
        message: t.isTransfer
            ? 'This transaction has two entries (a debit and a credit). Both will be deleted and balances recalculated.'
            : 'Delete "${t.description}" (${formatInr(t.amount.abs())})? Balances will be recalculated.',
        confirmText: 'Delete');
    if (!ok) return;
    try {
      await AppDatabase.instance.deleteTransaction(t.id);
      await st.refreshFinance();
      if (mounted) snack(context, 'Transaction deleted');
    } on ValidationException catch (e) {
      if (mounted) showErrorDialog(context, e.message);
    }
  }

  /// Opens the edit form; [complete] = "Mark as actual" flow.
  void _edit(TxnRecord t, {bool complete = false}) => Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) =>
              TransactionFormPage(editId: t.id, completeMode: complete)));

  /// Bottom sheet with all details (including the original scheduled info)
  /// and the Edit / Delete / Mark-as-actual actions.
  void _details(TxnRecord t) {
    final cs = Theme.of(context).colorScheme;
    Widget row(String k, String v, {Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
                width: 110,
                child: Text(k, style: TextStyle(color: cs.onSurfaceVariant))),
            Expanded(child: Text(v, style: TextStyle(color: color, fontWeight: color != null ? FontWeight.w700 : null))),
          ]),
        );
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.description, style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 8),
              row('Value', '${formatInr(t.amount.abs())}  (${t.amount > 0 ? 'credit' : 'debit'})',
                  color: t.amount > 0 ? creditColor(ctx) : debitColor(ctx)),
              row('Category', '${t.categoryName} (${t.categoryType == 'transfer' ? 'Self transfer' : t.categoryType == 'repayment' ? 'Credit bill repayment' : t.amount > 0 ? 'Credit' : 'Deduct'})'),
              row('Account', t.accountName +
                  (t.isTransfer ? (t.amount < 0 ? '  →  ' : '  ←  ') + (t.otherAccountName ?? '') : '')),
              row('Date & time', fmtDateTime.format(t.dateTime)),
              row('Status', t.isScheduled ? 'Scheduled' : 'Actual'),
              if (t.completedAt != null && t.schedAmount != null)
                row('Completed on', fmtDateTime.format(t.completedAt!)),
              if (t.schedAmount != null) ...[
                const Divider(),
                Text(t.isScheduled ? 'Scheduled info' : 'Originally scheduled as',
                    style: Theme.of(ctx).textTheme.titleSmall),
                row('Date & time',
                    t.schedDateTime == null ? '-' : fmtDateTime.format(t.schedDateTime!)),
                row('Description', t.schedDescription ?? '-'),
                row('Value', formatInr(t.schedAmount!.abs()),
                    color: t.schedAmount! > 0 ? creditColor(ctx) : debitColor(ctx)),
              ],
              const SizedBox(height: 14),
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (t.isScheduled)
                  FilledButton.icon(
                    icon: const Icon(Icons.check),
                    label: const Text('Mark as actual'),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _edit(t, complete: true);
                    },
                  ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.edit),
                  label: const Text('Edit'),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _edit(t);
                  },
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete'),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _delete(t);
                  },
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // reload when finance data changed somewhere else in the app
    final v = context.select<AppState, int>((s) => s.financeVersion);
    if (v != _ver) {
      _ver = v;
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
    final cs = Theme.of(context).colorScheme;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Row(children: [
          OutlinedButton.icon(
            onPressed: _openFilter,
            icon: Icon(_f.isActive ? Icons.filter_alt : Icons.filter_alt_outlined),
            label: Text(_f.isActive ? 'Filters on' : 'Filter'),
          ),
          if (_f.isActive)
            TextButton(
                onPressed: () {
                  _f = const TxnFilter();
                  _load();
                },
                child: const Text('Clear')),
          const Spacer(),
          Text('${_items.length} entries',
              style: TextStyle(color: cs.onSurfaceVariant)),
        ]),
      ),
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _items.isEmpty
                ? const Center(child: Text('No transactions found'))
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 90),
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final t = _items[i];
                      final credit = t.amount > 0;
                      return ListTile(
                        onTap: () => _details(t),
                        leading: CircleAvatar(
                          backgroundColor: Color.alphaBlend(Color(t.accountColor), Theme.of(context).colorScheme.surface),
                          child: Icon(categoryIconFor(t.categoryIcon),
                              color: onColor(Color.alphaBlend(
                                  Color(t.accountColor),
                                  Theme.of(context).colorScheme.surface)),
                              size: 20),
                        ),
                        title: Text(t.description,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          '${fmtDateTime.format(t.dateTime)}  •  ${t.categoryName}\n'
                          '${t.accountName}${t.isTransfer ? (credit ? '  ←  ' : '  →  ') + (t.otherAccountName ?? '') : ''}',
                        ),
                        isThreeLine: true,
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(formatInr(t.amount.abs()),
                                style: TextStyle(
                                    fontWeight: FontWeight.w500,
                                    fontSize: 19,
                                    color: credit
                                        ? creditColor(context)
                                        : debitColor(context))),
                            const SizedBox(height: 4),
                            if (t.isScheduled)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                    color: Colors.orange.withValues(alpha: .2),
                                    borderRadius: BorderRadius.circular(8)),
                                child: const Text('Scheduled',
                                    style: TextStyle(
                                        fontSize: 11, color: Colors.orange)),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
      ),
    ]);
  }
}

/// Bottom sheet where the user builds a [TxnFilter].
class _FilterSheet extends StatefulWidget {
  final TxnFilter initial;
  const _FilterSheet({required this.initial});
  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late final TextEditingController _text =
      TextEditingController(text: widget.initial.text);
  late final TextEditingController _min = TextEditingController(
      text: widget.initial.minAmount == null
          ? ''
          : paiseToInput(widget.initial.minAmount!));
  late final TextEditingController _max = TextEditingController(
      text: widget.initial.maxAmount == null
          ? ''
          : paiseToInput(widget.initial.maxAmount!));
  late int? _acc = widget.initial.accountId;
  late int? _cat = widget.initial.categoryId;
  late String? _status = widget.initial.status;
  late String? _dir = widget.initial.direction;
  late DateTime? _from = widget.initial.from;
  late DateTime? _to = widget.initial.to;

  Future<void> _pick(bool from) async {
    final d = await showDatePicker(
        context: context,
        initialDate: (from ? _from : _to) ?? DateTime.now(),
        firstDate: DateTime(2000),
        lastDate: DateTime(2100));
    if (d != null) setState(() => from ? _from = d : _to = d);
  }

  @override
  Widget build(BuildContext context) {
    final st = context.read<AppState>();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Filter transactions',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              TextField(
                  controller: _text,
                  decoration: const InputDecoration(
                      labelText: 'Search description / category / account',
                      prefixIcon: Icon(Icons.search))),
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                value: _acc,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Bank account'),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('All')),
                  for (final a in st.accounts)
                    DropdownMenuItem<int?>(
                        value: a.id, child: Text(accountPath(a, st.accounts))),
                ],
                onChanged: (v) => setState(() => _acc = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                value: _cat,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Category'),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('All')),
                  for (final c in st.categories)
                    DropdownMenuItem<int?>(value: c.id, child: Text(c.name)),
                ],
                onChanged: (v) => setState(() => _cat = v),
              ),
              const SizedBox(height: 12),
              const Text('Status'),
              const SizedBox(height: 4),
              SegmentedButton<String?>(
                segments: const [
                  ButtonSegment(value: null, label: Text('All')),
                  ButtonSegment(value: 'actual', label: Text('Actual')),
                  ButtonSegment(value: 'scheduled', label: Text('Scheduled')),
                ],
                selected: {_status},
                onSelectionChanged: (s) => setState(() => _status = s.first),
              ),
              const SizedBox(height: 12),
              const Text('Type'),
              const SizedBox(height: 4),
              SegmentedButton<String?>(
                segments: const [
                  ButtonSegment(value: null, label: Text('All')),
                  ButtonSegment(value: 'credit', label: Text('Credit')),
                  ButtonSegment(value: 'debit', label: Text('Debit')),
                ],
                selected: {_dir},
                onSelectionChanged: (s) => setState(() => _dir = s.first),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                      onPressed: () => _pick(true),
                      child: Text(_from == null
                          ? 'From date'
                          : fmtDate.format(_from!))),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                      onPressed: () => _pick(false),
                      child:
                          Text(_to == null ? 'To date' : fmtDate.format(_to!))),
                ),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TextField(
                      controller: _min,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Min value')),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                      controller: _max,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Max value')),
                ),
              ]),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, const TxnFilter()),
                      child: const Text('Reset')),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(
                        context,
                        TxnFilter(
                          text: _text.text.trim(),
                          accountId: _acc,
                          categoryId: _cat,
                          status: _status,
                          direction: _dir,
                          from: _from,
                          to: _to,
                          minAmount: parsePaise(_min.text),
                          maxAmount: parsePaise(_max.text),
                        )),
                    child: const Text('Apply'),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
