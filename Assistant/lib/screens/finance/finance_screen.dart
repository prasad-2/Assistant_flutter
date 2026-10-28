// Finance tab: list of account cards + the full transaction list.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../db/app_database.dart';
import '../../models/models.dart';
import '../../providers/app_state.dart';
import '../../widgets/account_card.dart';
import '../../widgets/common.dart';
import 'account_actions.dart';
import 'account_detail.dart';
import 'debts_view.dart';
import 'loan_form.dart';
import 'loans_view.dart';
import 'transaction_form.dart';
import 'transactions_view.dart';

class FinanceScreen extends StatefulWidget {
  const FinanceScreen({super.key});
  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends State<FinanceScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 5, vsync: this);
  bool _reorder = false; // reorder (up / down) mode of the Accounts tab

  @override
  void initState() {
    super.initState();
    // rebuild when the tab changes (the reorder button is Accounts-tab only)
    _tab.addListener(() {
      if (mounted) setState(() {});
    });
  }

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

  /// "Add" menu of the Debts tab: a new person or a new entry.
  void _showDebtMenu() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.person_add_alt),
            title: const Text('Add person'),
            onTap: () {
              Navigator.pop(ctx);
              DebtActions.addPerson(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.swap_vert),
            title: const Text('Add debt entry (I lent / I borrowed)'),
            onTap: () {
              Navigator.pop(ctx);
              DebtActions.addEntry(context);
            },
          ),
        ]),
      ),
    );
  }

  /// Rows of ONE section ("Bank accounts" or "Credit accounts").
  ///
  /// The global list is in tree order. For a section we keep only accounts of
  /// that type, compute the indentation from ancestors that are in the SAME
  /// section (an account whose parent is in the other section starts a new
  /// root) and hide accounts below a collapsed same-section ancestor.
  List<AccountSummary> _sectionRows(AppState s, bool credit) {
    final byId = {for (final x in s.summaries) x.account.id!: x};
    final inSection = [for (final x in s.summaries) if (x.account.isCredit == credit) x];
    final parentsWithKids = {
      for (final x in inSection)
        if (x.account.parentId != null &&
            (byId[x.account.parentId]?.account.isCredit == credit))
          x.account.parentId!
    };
    final rows = <AccountSummary>[];
    for (final x in inSection) {
      var depth = 0;
      var hidden = false;
      var p = x.account.parentId;
      var guard = 0;
      while (p != null && guard++ < 100) {
        final pa = byId[p];
        if (pa == null) break;
        if (pa.account.isCredit == credit) {
          depth++;
          if (s.collapsedAccounts.contains(pa.account.id)) hidden = true;
        }
        p = pa.account.parentId;
      }
      if (hidden) continue;
      // same data, but with the section based depth / children flag
      rows.add(AccountSummary(
        account: x.account,
        depth: depth,
        parentName: x.parentName,
        hasChildren: parentsWithKids.contains(x.account.id),
        actual: x.actual,
        available: x.available,
        scheduledIn: x.scheduledIn,
        scheduledOut: x.scheduledOut,
      ));
    }
    return rows;
  }

  /// Moves an account up / down among its siblings and saves the order.
  Future<void> _move(AppState s, Account a, bool up) async {
    await AppDatabase.instance.moveAccount(a.id!, up: up);
    await s.refreshFinance();
  }

  /// One account card (normal mode or reorder mode).
  Widget _card(AppState s, AccountSummary x) {
    // siblings of the same type, in saved order -> which arrows are enabled
    final sibs = [
      for (final y in s.summaries)
        if (y.account.parentId == x.account.parentId &&
            y.account.isCredit == x.account.isCredit)
          y.account.id
    ];
    final i = sibs.indexOf(x.account.id);
    return AccountCard(
      summary: x,
      hidden: s.isHidden(x.account.id!),
      onToggleHidden: () => s.toggleAccountHidden(x.account.id!),
      expanded: !s.collapsedAccounts.contains(x.account.id),
      onToggleExpand: () => s.toggleCollapsed(x.account.id!),
      reorderMode: _reorder,
      onMoveUp: i > 0 ? () => _move(s, x.account, true) : null,
      onMoveDown: (i >= 0 && i < sibs.length - 1)
          ? () => _move(s, x.account, false)
          : null,
      // tap -> bank details (notes) + its transactions
      onTap: _reorder
          ? null
          : () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => AccountDetailPage(accountId: x.account.id!))),
      onEdit: () => AccountActions.openForm(context, x.account),
      onDelete: () => AccountActions.confirmAndDelete(context, x.account),
      onToggleRegular: () => AccountActions.toggleRegular(context, x.account),
    );
  }

  /// One account page: only bank accounts OR only credit accounts, so the two
  /// kinds never share a scroll view.
  Widget _accountList(AppState s, {required bool credit}) {
    final rows = _sectionRows(s, credit);
    if (rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
              credit
                  ? 'No credit accounts yet.\nAdd an account and choose type "Credit account".'
                  : 'No bank accounts yet.\nTap "Add" to create your first account.',
              textAlign: TextAlign.center),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 90),
      children: [
        if (_reorder)
          Card(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                  'Reorder mode: use the arrows to move a card up or down among its siblings. The order is saved automatically. Tap the tick when done.'),
            ),
          ),
        for (final x in rows) _card(s, x),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Finance'),
        actions: [
          if (_tab.index <= 1) // Accounts and Credit tabs
            IconButton(
              tooltip: _reorder ? 'Done reordering' : 'Reorder accounts',
              icon: Icon(_reorder ? Icons.check : Icons.swap_vert),
              onPressed: () => setState(() => _reorder = !_reorder),
            ),
          IconButton(
            tooltip: s.hideBalances ? 'Show balances' : 'Hide balances',
            icon: Icon(s.hideBalances ? Icons.visibility_off : Icons.visibility),
            onPressed: s.toggleHide,
          ),
        ],
        bottom: TabBar(controller: _tab, isScrollable: true, tabAlignment: TabAlignment.start, tabs: const [
          Tab(text: 'Accounts'),
          Tab(text: 'Credit'),
          Tab(text: 'Transactions'),
          Tab(text: 'Loans'),
          Tab(text: 'Debts'),
        ]),
      ),
      // the Add button depends on the visible tab
      floatingActionButton: ListenableBuilder(
        listenable: _tab,
        builder: (context, _) {
          switch (_tab.index) {
            case 3:
              return FloatingActionButton.extended(
                icon: const Icon(Icons.add),
                label: const Text('Add loan'),
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const LoanFormPage())),
              );
            case 4:
              return FloatingActionButton.extended(
                icon: const Icon(Icons.add),
                label: const Text('Add'),
                onPressed: () => _showDebtMenu(),
              );
            default:
              return FloatingActionButton.extended(
                icon: const Icon(Icons.add),
                label: const Text('Add'),
                onPressed: () => _showAddMenu(s),
              );
          }
        },
      ),
      body: TabBarView(controller: _tab, children: [
        // ── Accounts tab (normal bank accounts) ──
        _accountList(s, credit: false),
        // ── Credit tab (credit accounts, separate page / scroll) ──
        _accountList(s, credit: true),
        // ── Transactions tab ──
        const TransactionsView(),
        // ── Loans tab ──
        const LoansView(),
        // ── Debts tab ──
        const DebtsView(),
      ]),
    );
  }
}
