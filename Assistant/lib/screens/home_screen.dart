// Home tab: running clock, quick actions, regular accounts and pending todos.
//
// Layout: the clock, buttons and section titles are FIXED; only the accounts
// list and the todo list scroll (each inside its own Expanded area).
import 'dart:async';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/app_state.dart';
import '../utils/format.dart';
import '../widgets/account_card.dart';
import 'finance/account_detail.dart';
import 'finance/transaction_form.dart';
import 'finance/transactions_view.dart';
import 'todo/todo_form.dart';
import 'todo/todo_tile.dart';

class HomeScreen extends StatelessWidget {
  final VoidCallback onSeeAllTodos; // switches to the Todo tab
  const HomeScreen({super.key, required this.onSeeAllTodos});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final regular = s.summaries.where((x) => x.account.isRegular).toList();
    final pending = s.todos.where((t) => !t.isDone).toList();
    final tt = Theme.of(context).textTheme.titleMedium;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        actions: [
          IconButton(
            tooltip: s.hideBalances ? 'Show balances' : 'Hide balances',
            icon: Icon(s.hideBalances ? Icons.visibility_off : Icons.visibility),
            onPressed: s.toggleHide,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Column(children: [
          const _ClockCard(),
          const SizedBox(height: 10),
          // quick actions
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Add transaction'),
                onPressed: () {
                  if (s.accounts.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Add a bank account in the Finance tab first.')));
                    return;
                  }
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const TransactionFormPage()));
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.schedule),
                label: const Text('Scheduled'),
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const TransactionsPage(
                            title: 'Scheduled transactions',
                            initial: TxnFilter(status: 'scheduled')))),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Align(
              alignment: Alignment.centerLeft,
              child: Text('Regular accounts', style: tt)),
          const SizedBox(height: 6),
          // ── scrollable area 1: regular accounts (compact cards) ──
          if (regular.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                  'No regular accounts yet. Mark an account as "Regular" in the Finance tab to see it here.'),
            )
          else
            Expanded(
              child: ListView(children: [
                for (final r in regular)
                  AccountCard(
                    summary: r,
                    hidden: s.hideBalances,
                    size: AccountCardSize.compact,
                    showIndent: false,
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                AccountDetailPage(accountId: r.account.id!))),
                  ),
              ]),
            ),
          Row(children: [
            Expanded(child: Text('Todos', style: tt)),
            IconButton(
              tooltip: 'Add todo',
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const TodoFormPage())),
            ),
            TextButton(onPressed: onSeeAllTodos, child: const Text('See all')),
          ]),
          // ── scrollable area 2: pending todos ──
          if (pending.isEmpty)
            const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Nothing pending. 🎉'))
          else
            Expanded(
              child: ListView(children: [for (final t in pending) TodoTile(todo: t)]),
            ),
        ]),
      ),
    );
  }
}

/// Running date-time (dd-MMM-yyyy HH:mm:ss). It has its own timer/State so
/// only this small widget rebuilds every second.
class _ClockCard extends StatefulWidget {
  const _ClockCard();
  @override
  State<_ClockCard> createState() => _ClockCardState();
}

class _ClockCardState extends State<_ClockCard> {
  late Timer _t;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1),
        (_) => setState(() => _now = DateTime.now()));
  }

  @override
  void dispose() {
    _t.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.primaryContainer,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.access_time, size: 16, color: cs.onPrimaryContainer),
          const SizedBox(width: 8),
          Text(fmtClock.format(_now),
              style: TextStyle(
                  color: cs.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ]),
      ),
    );
  }
}
