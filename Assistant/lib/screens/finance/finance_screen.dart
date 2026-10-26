// Finance tab: list of account cards + the full transaction list.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../providers/app_state.dart';
import '../../widgets/account_card.dart';
import '../../widgets/common.dart';
import 'account_actions.dart';
import 'account_detail.dart';
import 'transaction_form.dart';
import 'transactions_view.dart';

class FinanceScreen extends StatefulWidget {
  const FinanceScreen({super.key});
  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends State<FinanceScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  /// "Add" button: choose between a new account and a new transaction.
  void _showAddMenu(AppState s) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.account_balance),
            title: const Text('Add bank account'),
            onTap: () {
              Navigator.pop(ctx);
              AccountActions.openForm(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.receipt_long),
            title: const Text('Add transaction'),
            onTap: () {
              Navigator.pop(ctx);
              if (s.accounts.isEmpty) {
                showErrorDialog(context, 'Add a bank account first.');
              } else {
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const TransactionFormPage()));
              }
            },
          ),
        ]),
      ),
    );
  }

  /// Accounts that are currently visible. The list is in tree order, so when
  /// an account is collapsed every following entry that is deeper than it
  /// (its whole nested subtree) is skipped until the next sibling/ancestor.
  List<AccountSummary> _visible(AppState s) {
    final out = <AccountSummary>[];
    int? hideBelowDepth;
    for (final x in s.summaries) {
      if (hideBelowDepth != null) {
        if (x.depth > hideBelowDepth) continue; // inside a collapsed subtree
        hideBelowDepth = null;
      }
      out.add(x);
      if (x.hasChildren && s.collapsedAccounts.contains(x.account.id)) {
        hideBelowDepth = x.depth;
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Finance'),
        actions: [
          IconButton(
            tooltip: s.hideBalances ? 'Show balances' : 'Hide balances',
            icon: Icon(s.hideBalances ? Icons.visibility_off : Icons.visibility),
            onPressed: s.toggleHide,
          ),
        ],
        bottom: TabBar(controller: _tab, tabs: const [
          Tab(text: 'Accounts'),
          Tab(text: 'Transactions'),
        ]),
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Add'),
        onPressed: () => _showAddMenu(s),
      ),
      body: TabBarView(controller: _tab, children: [
        // ── Accounts tab ──
        s.summaries.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                      'No bank accounts yet.\nTap "Add" to create your first account.',
                      textAlign: TextAlign.center),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                children: [
                  for (final x in _visible(s))
                    AccountCard(
                      summary: x,
                      hidden: s.hideBalances,
                      expanded: !s.collapsedAccounts.contains(x.account.id),
                      onToggleExpand: () => s.toggleCollapsed(x.account.id!),
                      // tap -> bank details (notes) + its transactions
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  AccountDetailPage(accountId: x.account.id!))),
                      onEdit: () => AccountActions.openForm(context, x.account),
                      onDelete: () =>
                          AccountActions.confirmAndDelete(context, x.account),
                      onToggleRegular: () =>
                          AccountActions.toggleRegular(context, x.account),
                    ),
                ],
              ),
        // ── Transactions tab ──
        const TransactionsView(),
      ]),
    );
  }
}
