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
import '../widgets/common.dart';
import 'category_chart_page.dart';
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
            tooltip: 'Charts',
            icon: const Icon(Icons.pie_chart_outline),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const CategoryChartPage())),
          ),
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
          if (regular.isNotEmpty) ...[
            const SizedBox(height: 8),
            _DailyLimitCard(
                available: s.regularAvailable,
                daysLeft: s.daysLeftInMonth,
                perDay: s.dailyLimit,
                originalPerDay: s.originalDailyLimit,
                spentToday: s.todayOut,
                receivedToday: s.todayIn,
                hidden: s.hideBalances),
          ],
          const SizedBox(height: 10),
          // quick actions
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.add),
                label: const FittedBox(child: Text('Transaction')),
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
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.schedule),
                label: const FittedBox(child: Text('Scheduled')),
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const TransactionsPage(
                            title: 'Scheduled transactions',
                            initial: TxnFilter(status: 'scheduled')))),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.pie_chart_outline),
                label: const FittedBox(child: Text('Charts')),
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const CategoryChartPage())),
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
                    hidden: s.isHidden(r.account.id!),
                    onToggleHidden: () => s.toggleAccountHidden(r.account.id!),
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
          // day name + date + running time; scales down on narrow screens
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(fmtClock.format(_now),
                  style: TextStyle(
                      color: cs.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      fontFeatures: const [FontFeature.tabularFigures()])),
            ),
          ),
        ]),
      ),
    );
  }
}

/// "Daily limit" card (positive values green, negative red).
///   * current limit  = available balance of the regular accounts / days left
///     (changes with every transaction)
///   * day-start limit = the same calculation with the balance at 12 am today
///     (fixed for the whole day, renews every midnight)
///   * spent / received today = actual debits / credits of the regular
///     accounts dated today
class _DailyLimitCard extends StatelessWidget {
  final int available; // sum of regular accounts' available balance now
  final int daysLeft;
  final int perDay; // current daily limit
  final int originalPerDay; // limit at the start of the day
  final int spentToday;
  final int receivedToday;
  final bool hidden;
  const _DailyLimitCard(
      {required this.available,
      required this.daysLeft,
      required this.perDay,
      required this.originalPerDay,
      required this.spentToday,
      required this.receivedToday,
      required this.hidden});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = cs.onSecondaryContainer;
    // Colours by sign: positive = green, negative = red, zero / hidden = normal.
    Color? sign(int v) => hidden || v == 0
        ? null
        : (v > 0 ? creditColor(context) : debitColor(context));
    final color = sign(perDay) ?? fg;
    // summary of today = received - spent (spent counts as negative)
    final net = receivedToday - spentToday;

    /// small label + value cell used in the second row
    Widget mini(String label, String value, {Color? valueColor}) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10, color: fg.withValues(alpha: .75))),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value,
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500, color: valueColor ?? fg)),
            ),
          ]),
        );

    return Card(
      margin: EdgeInsets.zero,
      color: cs.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        child: Column(children: [
          Row(children: [
            Icon(Icons.speed, color: fg),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Daily limit',
                    style: TextStyle(fontSize: 12, color: fg.withValues(alpha: .8))),
                Text(
                    '${formatInr(available, hidden: hidden)}  ÷  $daysLeft day${daysLeft == 1 ? '' : 's'} left',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: fg.withValues(alpha: .8))),
              ]),
            ),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 170),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text('${formatInr(perDay, hidden: hidden)} / day',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w500,
                        color: sign(perDay) ?? fg)),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          Divider(height: 1, color: fg.withValues(alpha: .2)),
          const SizedBox(height: 6),
          Row(children: [
            mini('Day-start limit', '${formatInr(originalPerDay, hidden: hidden)} / day',
                valueColor: sign(originalPerDay)),
            mini('Spent today', formatInr(spentToday, hidden: hidden),
                valueColor: sign(-spentToday)),
            mini('Received today', formatInr(receivedToday, hidden: hidden),
                valueColor: sign(receivedToday)),
            mini('Summary', formatInr(net, hidden: hidden), valueColor: sign(net)),
          ]),
        ]),
      ),
    );
  }
}
