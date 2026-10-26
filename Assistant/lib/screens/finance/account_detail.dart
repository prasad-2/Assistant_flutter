// Detail page of one bank account (opened by tapping an account card).
//   Tab 1 "Details"      – card, owner, type, parent/children, notes...
//   Tab 2 "Transactions" – the account's transactions (with filter)
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../providers/app_state.dart';
import '../../utils/format.dart';
import '../../widgets/account_card.dart';
import '../../widgets/common.dart';
import 'account_actions.dart';
import 'transaction_form.dart';
import 'transactions_view.dart';

class AccountDetailPage extends StatelessWidget {
  final int accountId;
  const AccountDetailPage({super.key, required this.accountId});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final matches = s.summaries.where((x) => x.account.id == accountId);
    if (matches.isEmpty) {
      // account was deleted: nothing to show
      return const Scaffold(body: Center(child: Text('Account not found')));
    }
    final sum = matches.first;
    final a = sum.account;
    final children = s.summaries
        .where((x) => x.account.parentId == a.id)
        .map((x) => x.account.name)
        .toList();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(a.name),
          actions: [
            IconButton(
              tooltip: s.hideBalances ? 'Show balances' : 'Hide balances',
              icon: Icon(s.hideBalances ? Icons.visibility_off : Icons.visibility),
              onPressed: s.toggleHide,
            ),
            IconButton(
              tooltip: 'Edit',
              icon: const Icon(Icons.edit),
              onPressed: () => AccountActions.openForm(context, a),
            ),
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'regular') AccountActions.toggleRegular(context, a);
                if (v == 'delete') {
                  final deleted = await AccountActions.confirmAndDelete(context, a);
                  if (deleted && context.mounted) Navigator.pop(context);
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                    value: 'regular',
                    child: Text(a.isRegular ? 'Remove from regular' : 'Mark as regular')),
                const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ],
          bottom: const TabBar(tabs: [Tab(text: 'Details'), Tab(text: 'Transactions')]),
        ),
        floatingActionButton: FloatingActionButton(
          tooltip: 'Add transaction',
          onPressed: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const TransactionFormPage())),
          child: const Icon(Icons.add),
        ),
        body: TabBarView(children: [
          // ── Details tab ──
          ListView(
            padding: const EdgeInsets.all(12),
            children: [
              AccountCard(summary: sum, hidden: s.hideBalances, showIndent: false),
              const SizedBox(height: 6),
              Card(
                child: Column(children: [
                  _row(Icons.account_balance, 'Bank / account', a.name),
                  _row(Icons.person, 'Owner', a.owner),
                  _row(Icons.credit_card, 'Account type',
                      a.isCredit ? 'Credit account' : 'Normal account'),
                  if (a.isCredit) ...[
                    _row(Icons.speed, 'Credit limit',
                        formatInr(a.creditLimit, hidden: s.hideBalances)),
                    // total spend = credit limit - available balance
                    _row(
                        Icons.shopping_bag_outlined,
                        'Total spend',
                        formatInr(
                            a.creditLimit > sum.available
                                ? a.creditLimit - sum.available
                                : 0,
                            hidden: s.hideBalances)),
                  ],
                  _row(Icons.account_tree, 'Parent account',
                      a.parentId == null ? 'None (top level)' : (sum.parentName ?? '-')),
                  if (children.isNotEmpty)
                    _row(Icons.subdirectory_arrow_right, 'Child accounts',
                        children.join(', ')),
                  _row(Icons.star, 'Regular account',
                      a.isRegular ? 'Yes (shown on Home)' : 'No'),
                ]),
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const Icon(Icons.notes),
                      const SizedBox(width: 8),
                      Text('Notes', style: Theme.of(context).textTheme.titleMedium),
                    ]),
                    const SizedBox(height: 8),
                    // SelectableText so account numbers etc. can be copied
                    SelectableText(
                      a.notes.isEmpty ? 'No notes added for this account.' : a.notes,
                      style: a.notes.isEmpty
                          ? TextStyle(
                              fontStyle: FontStyle.italic,
                              color: Theme.of(context).colorScheme.onSurfaceVariant)
                          : null,
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () => AccountActions.openForm(context, a),
                        icon: const Icon(Icons.edit_note),
                        label: const Text('Edit notes'),
                      ),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 80),
            ],
          ),
          // ── Transactions tab ──
          TransactionsView(initial: TxnFilter(accountId: a.id)),
        ]),
      ),
    );
  }

  Widget _row(IconData icon, String k, String v) => ListTile(
        dense: true,
        leading: Icon(icon, size: 20),
        title: Text(k, style: const TextStyle(fontSize: 12)),
        subtitle: Text(v, style: const TextStyle(fontSize: 15)),
      );
}
