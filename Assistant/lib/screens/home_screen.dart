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
import '../widgets/daily_limit_details.dart';
import 'category_chart_page.dart';
import 'finance/account_detail.dart';
import 'finance/transaction_form.dart';
import 'finance/transactions_view.dart';
import 'todo/todo_form.dart';
import 'todo/todo_tile.dart';

class HomeScreen extends StatelessWidget {
  final VoidCallback onSeeAllTodos; // switches to the Todo tab
  const HomeScreen({super.key, required this.onSeeAllTodos});

  /// Header of a collapsible section: title + arrow (tap to expand/collapse)
  /// and optional action buttons on the right.
  Widget _header(BuildContext context, String title, bool open, VoidCallback toggle,
      List<Widget> actions) {
    final tt = Theme.of(context).textTheme.titleMedium;
    return Row(children: [
      Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: toggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(children: [
              AnimatedRotation(
                turns: open ? 0 : -.25, // arrow points down when open
                duration: const Duration(milliseconds: 180),
                child: const Icon(Icons.expand_more),
              ),
              const SizedBox(width: 4),
              Text(title, style: tt),
            ]),
          ),
        ),
      ),
      ...actions,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final regular = s.summaries.where((x) => x.account.isRegular).toList();
    final pending = s.todos.where((t) => !t.isDone).toList();

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
          // each block below can be switched off in Settings -> Home screen
          if (s.showDailyLimit && regular.isNotEmpty) ...[
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

          // ── accordion 1: regular accounts ──
          if (s.showRegularAccounts) ...[
            _header(context, 'Regular accounts', s.regularOpen,
                () => s.toggleHomeSection(accounts: true), [
              IconButton(
                tooltip: 'Add transaction',
                icon: const Icon(Icons.add_circle_outline),
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
              IconButton(
                tooltip: 'Scheduled transactions',
                icon: const Icon(Icons.schedule),
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const TransactionsPage(
                            title: 'Scheduled transactions',
                            initial: TxnFilter(status: 'scheduled')))),
              ),
            ]),
            if (s.regularOpen)
              regular.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                          'No regular accounts yet. Mark an account as "Regular" in the Finance tab to see it here.'),
                    )
                  : Expanded(
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
          ],

          // ── accordion 2: todos ──
          if (s.showTodoList) ...[
            _header(context, 'Todos', s.todosOpen,
                () => s.toggleHomeSection(accounts: false), [
              IconButton(
                tooltip: 'Add todo',
                icon: const Icon(Icons.add_circle_outline),
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const TodoFormPage())),
              ),
              TextButton(onPressed: onSeeAllTodos, child: const Text('See all')),
            ]),
            if (s.todosOpen)
              pending.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('Nothing pending. 🎉'))
                  : Expanded(
                      child: ListView(
                          children: [for (final t in pending) TodoTile(todo: t)]),
                    ),
          ],
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
    final style = TextStyle(
        color: cs.onPrimaryContainer,
        fontWeight: FontWeight.w600,
        fontSize: 13,
        fontFeatures: const [FontFeature.tabularFigures()]);

    /// one clock part; scales down on very narrow screens
    Widget part(String text, Alignment align) => Align(
          alignment: align,
          child: FittedBox(
              fit: BoxFit.scaleDown, child: Text(text, style: style)),
        );

    // date on the left, day in the middle, time on the right (no icon)
    return Card(
      color: cs.primaryContainer,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        child: Row(children: [
          Expanded(child: part(fmtClockDate.format(_now), Alignment.centerLeft)),
          Expanded(child: part(fmtClockDay.format(_now), Alignment.center)),
          Expanded(child: part(fmtClockTime.format(_now), Alignment.centerRight)),
        ]),
      ),
    );
  }
}

/// "Daily limit" card, laid out on several lines:
///   1. current daily limit (changes with every transaction) + how it is made
///   2. a PROGRESS BAR of today's spending against the day-start limit
///      (spent / day-start limit) with spent and remaining under it
///   3. two small rows of values: day-start limit | remaining,
///      received today | today's summary
/// Positive values are green, negative values red.
class _DailyLimitCard extends StatelessWidget {
  final int available; // sum of regular accounts' available balance now
  final int daysLeft;
  final int perDay; // current daily limit
  final int originalPerDay; // limit at the start of the day (fixed all day)
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
    String m(int v) => formatInr(v, hidden: hidden);

    // positive = green, negative = red, zero / hidden = normal
    Color? sign(int v) => hidden || v == 0
        ? null
        : (v > 0 ? creditColor(context) : debitColor(context));

    final remaining = originalPerDay - spentToday; // left of the day's limit
    final over = spentToday > 0 && remaining < 0;

    // progress = spent / day-start limit (full when there is no limit left)
    final ratio = originalPerDay > 0
        ? (spentToday / originalPerDay).clamp(0.0, 1.0)
        : (spentToday > 0 ? 1.0 : 0.0);
    final barColor = over || originalPerDay <= 0 && spentToday > 0
        ? debitColor(context)
        : (ratio >= .8 ? Colors.orange : creditColor(context));

    /// label above value; [end] right-aligns the cell
    Widget cell(String label, String value,
            {Color? color, bool end = false, VoidCallback? onTap}) =>
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Column(
                  crossAxisAlignment:
                      end ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  children: [
                    Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(label,
                              style: TextStyle(
                                  fontSize: 11, color: fg.withValues(alpha: .75))),
                          // info icon: tap to see the calculation / recalculate
                          if (onTap != null)
                            Padding(
                              padding: const EdgeInsets.only(left: 3),
                              child: Icon(Icons.info_outline,
                                  size: 12, color: fg.withValues(alpha: .75)),
                            ),
                        ]),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: end ? Alignment.centerRight : Alignment.centerLeft,
                      child: Text(value,
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: color ?? fg)),
                    ),
                  ]),
            ),
          ),
        );

    return Card(
      margin: EdgeInsets.zero,
      color: cs.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // ── 1. current limit ──
          Row(children: [
            Icon(Icons.speed, color: fg),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Daily limit',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: fg.withValues(alpha: .9))),
                Text('${m(available)}  ÷  $daysLeft day${daysLeft == 1 ? '' : 's'} left',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: fg.withValues(alpha: .75))),
              ]),
            ),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 170),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text('${m(perDay)} / day',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w500,
                        color: sign(perDay) ?? fg)),
              ),
            ),
          ]),
          const SizedBox(height: 12),

          // ── 2. progress bar: spent against the day-start limit ──
          Row(children: [
            Text("Today's usage",
                style: TextStyle(fontSize: 11, color: fg.withValues(alpha: .75))),
            const Spacer(),
            if (!hidden)
              Text(
                  originalPerDay > 0
                      ? '${(spentToday / originalPerDay * 100).round()}% used'
                      : (spentToday > 0 ? 'no limit left' : '0% used'),
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: over ? debitColor(context) : fg.withValues(alpha: .85))),
          ]),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 10,
              color: barColor,
              backgroundColor: fg.withValues(alpha: .15),
            ),
          ),
          // remaining / day-start limit, e.g. 125.00 / 500.00 (no label)
          const SizedBox(height: 4),
          Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text.rich(TextSpan(children: [
                TextSpan(
                    text: m(remaining),
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: sign(remaining) ?? fg)),
                TextSpan(
                    text: ' / ${m(originalPerDay)}',
                    style: TextStyle(fontSize: 15, color: fg.withValues(alpha: .85))),
              ])),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Divider(height: 1, color: fg.withValues(alpha: .2)),
          ),

          // ── the two remaining figures on ONE line ──
          Row(children: [
            cell('Day-start limit', '${m(originalPerDay)} / day',
                color: sign(originalPerDay),
                onTap: () => showDailyLimitDetails(context, hidden: hidden)),
            const SizedBox(width: 12),
            cell('Received today', m(receivedToday),
                color: sign(receivedToday), end: true),
          ]),
        ]),
      ),
    );
  }
}
