// One person's debt page: balance summary, entries, settle up (setoff),
// and linking entries to real bank transactions.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../db/app_database.dart';
import '../../db/debt_repository.dart';
import '../../models/debt_models.dart';
import '../../models/models.dart';
import '../../providers/app_state.dart';
import '../../utils/format.dart';
import '../../utils/icons.dart';
import '../../widgets/amount_field.dart';
import '../../widgets/bank_link_picker.dart';
import '../../widgets/common.dart';
import '../../widgets/form_widgets.dart';
import 'debt_entry_form.dart';
import 'debts_view.dart';

class DebtPersonPage extends StatefulWidget {
  final int personId;
  const DebtPersonPage({super.key, required this.personId});
  @override
  State<DebtPersonPage> createState() => _DebtPersonPageState();
}

class _DebtPersonPageState extends State<DebtPersonPage> {
  List<DebtEntry> _entries = [];
  bool _loading = true;
  int _ver = -1;

  DebtRepository get _repo => DebtRepository.instance;

  /// Reloads this person's entries.
  Future<void> _load() async {
    final e = await _repo.entries(widget.personId);
    if (!mounted) return;
    setState(() {
      _entries = e;
      _loading = false;
    });
  }

  Future<bool> _run(Future<void> Function() action, {String? done}) async {
    final st = context.read<AppState>();
    try {
      await action();
      await st.refreshFinance();
      if (done != null && mounted) snack(context, done);
      return true;
    } on ValidationException catch (e) {
      if (mounted) showErrorDialog(context, e.message);
      return false;
    }
  }

  /// Settle up (debt setoff): records an opposite entry for the amount paid.
  Future<void> _settle(DebtPerson p) async {
    final amount = TextEditingController(text: paiseToInput(p.net.abs()));
    var bankOn = false;
    int? account;
    var status = 'actual';
    final theyPayMe = p.net > 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Settle up'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(theyPayMe
                ? '${p.name} pays you back. Balance ${formatInr(p.net.abs())}.'
                : 'You pay ${p.name} back. Balance ${formatInr(p.net.abs())}.'),
            const SizedBox(height: 12),
            AmountField(controller: amount, label: 'Amount settled'),
            const SizedBox(height: 8),
            BankLinkPicker(
              switchTitle: 'Also create a bank transaction',
              helper: theyPayMe ? 'Credits the account' : 'Deducts from the account',
              onChanged: (on, acc, st) {
                bankOn = on;
                account = acc;
                status = st;
              },
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Settle')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (bankOn && account == null) {
      showErrorDialog(context, 'Select the bank account for the bank transaction.');
      return;
    }
    await _run(
        () => _repo.settle(
              person: p,
              amount: parsePaise(amount.text) ?? 0,
              link: bankOn ? BankLink(account!, status) : null,
            ),
        done: 'Settled');
  }

  /// Lets the user pick an EXISTING bank transaction of the matching money
  /// direction (lent = debit, borrowed = credit) and links it to the entry.
  Future<void> _linkExisting(DebtEntry e) async {
    final list = await AppDatabase.instance.queryTransactions(
        TxnFilter(direction: e.isBankDebit ? 'debit' : 'credit'));
    if (!mounted) return;
    final picked = await showModalBottomSheet<TxnRecord>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        var q = '';
        return StatefulBuilder(builder: (ctx, setS) {
          final shown = list
              .where((t) =>
                  q.isEmpty ||
                  t.description.toLowerCase().contains(q) ||
                  t.accountName.toLowerCase().contains(q))
              .take(80)
              .toList();
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: .8,
            maxChildSize: .95,
            builder: (ctx, scroll) => Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: TextField(
                    decoration: InputDecoration(
                        hintText: 'Search ${e.isBankDebit ? 'debit' : 'credit'} transactions',
                        prefixIcon: const Icon(Icons.search),
                        isDense: true),
                    onChanged: (v) => setS(() => q = v.toLowerCase().trim()),
                  ),
                ),
                Expanded(
                  child: shown.isEmpty
                      ? const Center(child: Text('No matching transactions'))
                      : ListView.builder(
                          controller: scroll,
                          itemCount: shown.length,
                          itemBuilder: (_, i) {
                            final t = shown[i];
                            return ListTile(
                              leading: Icon(categoryIconFor(t.categoryIcon)),
                              title: Text(t.description,
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text(
                                  '${fmtDateTime.format(t.dateTime)} • ${t.accountName}'),
                              trailing: Text(formatInr(t.amount.abs()),
                                  style: const TextStyle(fontSize: 16)),
                              onTap: () => Navigator.pop(ctx, t),
                            );
                          },
                        ),
                ),
              ]),
            ),
          );
        });
      },
    );
    if (picked != null) {
      await _run(() => _repo.linkTxn(e.id!, picked.id), done: 'Linked to bank transaction');
    }
  }

  Future<void> _deleteEntry(DebtEntry e) async {
    final ok = await confirmDialog(context,
        title: 'Delete entry?',
        message:
            'Delete "${e.description}"? ${e.txnId != null ? 'The linked bank transaction is kept.' : ''}',
        confirmText: 'Delete');
    if (ok) await _run(() => _repo.deleteEntry(e.id!), done: 'Entry deleted');
  }

  Future<void> _deletePerson(DebtPerson p) async {
    final ok = await confirmDialog(context,
        title: 'Delete person?',
        message:
            'Delete ${p.name} and all ${p.entries} entries? Bank transactions already created are kept.',
        confirmText: 'Delete');
    if (ok && await _run(() => _repo.deletePerson(p.id), done: 'Deleted') && mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final ver = context.select<AppState, int>((s) => s.financeVersion);
    if (ver != _ver) {
      _ver = ver;
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
    final found = st.people.where((p) => p.id == widget.personId);
    if (found.isEmpty) {
      return const Scaffold(body: Center(child: Text('Person not found')));
    }
    final p = found.first;
    final h = st.hideBalances;
    final Color color = p.settled
        ? Theme.of(context).colorScheme.primary
        : (p.owesMe ? Colors.green.shade700 : Colors.red.shade600);

    return Scaffold(
      appBar: AppBar(
        title: Text(p.name),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'rename') {
                await DebtActions.addPerson(context, initial: p.name, id: p.id);
              }
              if (v == 'delete') _deletePerson(p);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('Rename')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          FormBanner(
            color: color,
            icon: p.settled ? Icons.handshake_outlined : (p.owesMe ? Icons.call_made : Icons.call_received),
            title: p.settled
                ? 'All settled up'
                : p.owesMe
                    ? '${p.name} owes you'
                    : 'You owe ${p.name}',
            subtitle: 'Lent ${formatInr(p.lent, hidden: h)}  •  Borrowed ${formatInr(p.borrowed, hidden: h)}',
            trailing: p.settled
                ? null
                : Text(formatInr(p.net.abs(), hidden: h),
                    style: const TextStyle(
                        color: Colors.white, fontSize: 22, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => DebtActions.addEntry(context, personId: p.id),
                icon: const Icon(Icons.add),
                label: const Text('Add entry'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: p.settled ? null : () => _settle(p),
                icon: const Icon(Icons.handshake_outlined),
                label: const Text('Settle up'),
              ),
            ),
          ]),
          const SizedBox(height: 14),
          Text('Entries', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          if (_loading)
            const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
          else if (_entries.isEmpty)
            const Padding(padding: EdgeInsets.all(16), child: Text('No entries yet'))
          else
            for (final e in _entries) _entryTile(context, p, e, h),
        ],
      ),
    );
  }

  /// One entry row. Colour: green = they owe me, red = I owe, primary = setoff.
  Widget _entryTile(BuildContext context, DebtPerson p, DebtEntry e, bool hidden) {
    final cs = Theme.of(context).colorScheme;
    final Color c = e.isSetoff
        ? cs.primary
        : (e.isLent ? creditColor(context) : debitColor(context));
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 2, 8),
        child: Row(children: [
          CircleAvatar(
            backgroundColor: c.withValues(alpha: .16),
            child: Icon(
                e.isSetoff
                    ? Icons.handshake_outlined
                    : (e.isLent ? Icons.call_made : Icons.call_received),
                color: c,
                size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.description,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              Row(children: [
                Flexible(
                  child: Text(
                      '${fmtDateTime.format(e.dateTime)} • ${e.isSetoff ? 'Setoff' : (e.isLent ? 'I lent' : 'I borrowed')}',
                      style: Theme.of(context).textTheme.bodySmall),
                ),
                if (e.txnId != null)
                  const Padding(
                      padding: EdgeInsets.only(left: 6),
                      child: Icon(Icons.link, size: 15)),
              ]),
            ]),
          ),
          const SizedBox(width: 8),
          Text(formatInr(e.amount, hidden: hidden),
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: c)),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'edit') {
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => DebtEntryFormPage(edit: e, personId: e.personId)));
              }
              if (v == 'link') _linkExisting(e);
              if (v == 'unlink') _run(() => _repo.linkTxn(e.id!, null), done: 'Unlinked');
              if (v == 'delete') _deleteEntry(e);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
              if (e.txnId == null)
                const PopupMenuItem(value: 'link', child: Text('Link bank transaction'))
              else
                const PopupMenuItem(value: 'unlink', child: Text('Unlink bank transaction')),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ]),
      ),
    );
  }
}
