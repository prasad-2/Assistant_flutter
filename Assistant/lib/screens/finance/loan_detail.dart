// Loan detail page:
//   summary card -> loan terms -> actions (Calculate EMI, Generate schedule,
//   Foreclose) -> list of EMI entries (edit / mark paid / create bank txn).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../db/loan_repository.dart';
import '../../models/loan_models.dart';
import '../../models/models.dart';
import '../../providers/app_state.dart';
import '../../utils/format.dart';
import '../../utils/loan_math.dart';
import '../../widgets/amount_field.dart';
import '../../widgets/common.dart';
import '../../widgets/loan_card.dart';
import 'loan_form.dart';

class LoanDetailPage extends StatelessWidget {
  final int loanId;
  const LoanDetailPage({super.key, required this.loanId});

  LoanRepository get _repo => LoanRepository.instance;

  // ───────────────────────── actions ─────────────────────────

  /// Runs a repository action, refreshes lists and shows validation errors.
  Future<bool> _run(BuildContext context, Future<void> Function() action,
      {String? done}) async {
    final st = context.read<AppState>();
    try {
      await action();
      await st.refreshFinance();
      if (done != null && context.mounted) snack(context, done);
      return true;
    } on ValidationException catch (e) {
      if (context.mounted) showErrorDialog(context, e.message);
      return false;
    }
  }

  /// EMI calculator dialog. Shows the calculated EMI, which the user may EDIT:
  /// the interest % is then calculated in reverse (so that these EMIs repay
  /// the loan) and both the EMI and the interest are saved.
  Future<void> _calculateEmi(BuildContext context, LoanSummary s) async {
    final l = s.loan;
    final n = l.installments;
    final computed = calcEmi(l.principal, l.rate, n, l.freqValue, l.freqUnit);
    final emiC = TextEditingController(text: paiseToInput(computed));
    int? saveEmi;
    double? saveRate;

    final save = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        final emi = parsePaise(emiC.text) ?? 0;
        final edited = emi != computed;
        // untouched EMI keeps the entered rate; an edited EMI recalculates it
        final rate = edited
            ? solveAnnualRate(
                principal: l.principal,
                emi: emi,
                n: n,
                freqValue: l.freqValue,
                freqUnit: l.freqUnit)
            : l.rate;
        final rounded = rate == null ? null : double.parse(rate.toStringAsFixed(2));
        final valid = emi > 0 && rounded != null && rounded <= 100;
        final total = emi * n;
        final interest = total - l.principal;
        return AlertDialog(
          icon: const Icon(Icons.calculate),
          title: const Text('EMI calculation'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _kv('Loan value', formatInr(l.principal)),
              _kv('Instalments', '$n  (${l.frequencyText.toLowerCase()})'),
              const SizedBox(height: 10),
              AmountField(
                controller: emiC,
                label: 'EMI amount (you can edit it)',
                onChanged: (_) => setS(() {}),
              ),
              const SizedBox(height: 10),
              _kv(
                  edited ? 'Interest (recalculated)' : 'Interest',
                  rounded == null
                      ? 'EMI too low to repay the loan'
                      : '${rounded.toStringAsFixed(2)}% per year',
                  bold: true),
              if (edited) _kv('Entered interest', '${l.rate}% per year'),
              _kv('Total interest', valid ? formatInr(interest < 0 ? 0 : interest) : '-'),
              _kv('Total payable', valid ? formatInr(total) : '-'),
              if (s.hasSchedule)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                      'Existing EMI entries are not changed. Use "Regenerate schedule" to apply the new values.',
                      style: Theme.of(ctx).textTheme.bodySmall),
                ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Close')),
            FilledButton(
                onPressed: valid
                    ? () {
                        saveEmi = emi;
                        saveRate = edited ? rounded : l.rate;
                        Navigator.pop(ctx, true);
                      }
                    : null,
                child: Text(edited ? 'Save EMI & interest' : 'Use as EMI amount')),
          ],
        );
      }),
    );
    if (save == true && context.mounted && saveEmi != null) {
      await _run(context,
          () => _repo.saveEmiAndRate(l.id!, saveEmi!, saveRate!),
          done: 'EMI amount and interest saved');
    }
  }

  /// Generates the EMI entries (replaces existing ones after confirmation).
  Future<void> _generate(BuildContext context, LoanSummary s) async {
    var loan = s.loan;
    if (loan.emiAmount <= 0) {
      // calculate automatically when the user skipped the calculation step
      final emi = calcEmi(loan.principal, loan.rate, loan.installments,
          loan.freqValue, loan.freqUnit);
      loan = loan.copyWith(emiAmount: emi);
    }
    if (s.hasSchedule) {
      final ok = await confirmDialog(context,
          title: 'Generate again?',
          message:
              'All ${s.emis.length} existing EMI entries (including paid marks) will be replaced by a new schedule.',
          confirmText: 'Replace');
      if (!ok || !context.mounted) return;
    }
    await _run(context, () async {
      await _repo.setEmiAmount(loan.id!, loan.emiAmount);
      await _repo.generateSchedule(loan);
    }, done: 'EMI schedule generated');
  }

  Future<void> _foreclose(BuildContext context, LoanSummary s) async {
    final ok = await confirmDialog(context,
        title: 'Foreclose loan?',
        message:
            'Outstanding ${formatInr(s.outstanding)} + foreclosure charge (${s.loan.foreclosePct}%) = ${formatInr(s.foreclosureAmount)}.\n\nThe loan will be closed and all unpaid EMIs cancelled.',
        confirmText: 'Foreclose');
    if (ok && context.mounted) {
      await _run(context, () => _repo.foreclose(s.loan.id!), done: 'Loan closed');
    }
  }

  Future<void> _delete(BuildContext context, LoanSummary s) async {
    final ok = await confirmDialog(context,
        title: 'Delete loan?',
        message:
            'Delete "${s.loan.name}" and its ${s.emis.length} EMI entries? Bank transactions already created stay.',
        confirmText: 'Delete');
    if (!ok || !context.mounted) return;
    if (await _run(context, () => _repo.deleteLoan(s.loan.id!), done: 'Loan deleted') &&
        context.mounted) {
      Navigator.pop(context);
    }
  }

  /// Edit one EMI: due date and amount.
  Future<void> _editEmi(BuildContext context, LoanEmi e) async {
    final amount = TextEditingController(text: paiseToInput(e.emi));
    var due = e.dueDate;
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text('Edit EMI #${e.no}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () async {
                final d = await showDatePicker(
                    context: ctx,
                    initialDate: due,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100));
                if (d != null) setS(() => due = d);
              },
              child: InputDecorator(
                decoration: const InputDecoration(
                    labelText: 'EMI date', prefixIcon: Icon(Icons.event)),
                child: Text(fmtDate.format(due)),
              ),
            ),
            const SizedBox(height: 12),
            AmountField(controller: amount, label: 'EMI amount'),
            const SizedBox(height: 8),
            Text('Interest part stays ${formatInr(e.interestPart)}; the rest becomes principal.',
                style: Theme.of(ctx).textTheme.bodySmall),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (res == true && context.mounted) {
      await _run(context,
          () => _repo.updateEmi(e, due, parsePaise(amount.text) ?? 0),
          done: 'EMI updated');
    }
  }

  /// Mark an EMI as paid: paid date + optional late-payment penalty.
  Future<void> _markPaid(BuildContext context, LoanSummary s, LoanEmi e) async {
    var paid = DateTime.now();
    final penalty = TextEditingController();
    void suggest() {
      final late = DateTime(paid.year, paid.month, paid.day)
          .isAfter(DateTime(e.dueDate.year, e.dueDate.month, e.dueDate.day));
      final p = late ? (e.emi * s.loan.penaltyPct / 100).round() : 0;
      penalty.text = p > 0 ? paiseToInput(p) : '';
    }

    suggest();
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text('EMI #${e.no} paid'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () async {
                final d = await showDatePicker(
                    context: ctx,
                    initialDate: paid,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100));
                if (d != null) setS(() {
                  paid = d;
                  suggest();
                });
              },
              child: InputDecorator(
                decoration: const InputDecoration(
                    labelText: 'Paid on', prefixIcon: Icon(Icons.event_available)),
                child: Text(fmtDate.format(paid)),
              ),
            ),
            const SizedBox(height: 12),
            AmountField(
              controller: penalty,
              label: 'Late penalty (${s.loan.penaltyPct}%)',
              helper: 'Filled automatically when paid after the due date',
              required: false,
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Mark paid')),
          ],
        ),
      ),
    );
    if (res == true && context.mounted) {
      await _run(context,
          () => _repo.markPaid(e.id, paid, parsePaise(penalty.text) ?? 0),
          done: 'EMI marked as paid');
    }
  }

  /// Create ONE bank transaction for this EMI (asks scheduled / actual and
  /// the source account; default description names the EMI date).
  Future<void> _createTxn(BuildContext context, LoanSummary s, LoanEmi e) async {
    final st = context.read<AppState>();
    if (st.accounts.isEmpty) {
      showErrorDialog(context, 'Add a bank account first.');
      return;
    }
    int? account = st.accounts.length == 1 ? st.accounts.first.id : null;
    var status = 'actual';
    final desc = TextEditingController(
        text: 'Emi payment for ${fmtDate.format(e.dueDate)}');
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Create bank transaction'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('EMI amount: ${formatInr(e.emi)}  (deduct)',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                value: account,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'Pay from bank account',
                    prefixIcon: Icon(Icons.account_balance)),
                items: [
                  for (final a in st.accounts)
                    DropdownMenuItem(
                        value: a.id,
                        child: Text(accountPath(a, st.accounts),
                            overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setS(() => account = v),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: desc,
                decoration: const InputDecoration(
                    labelText: 'Description', prefixIcon: Icon(Icons.short_text)),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                        value: 'actual',
                        label: Text('Actual'),
                        icon: Icon(Icons.check_circle_outline)),
                    ButtonSegment(
                        value: 'scheduled',
                        label: Text('Scheduled'),
                        icon: Icon(Icons.schedule)),
                  ],
                  selected: {status},
                  onSelectionChanged: (v) => setS(() => status = v.first),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                  status == 'actual'
                      ? 'Dated now; the EMI is also marked as paid.'
                      : 'Dated on the EMI date; stays pending until you pay.',
                  style: Theme.of(ctx).textTheme.bodySmall),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
                onPressed: account == null ? null : () => Navigator.pop(ctx, true),
                child: const Text('Create')),
          ],
        ),
      ),
    );
    if (res == true && context.mounted) {
      await _run(
          context,
          () => _repo.createBankTransaction(
              emi: e,
              accountId: account!,
              status: status,
              description: desc.text.trim().isEmpty
                  ? 'Emi payment for ${fmtDate.format(e.dueDate)}'
                  : desc.text.trim()),
          done: 'Bank transaction created');
    }
  }

  // ───────────────────────── UI ─────────────────────────

  Widget _kv(String k, String v, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(k)),
          Text(v, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final found = st.loans.where((x) => x.loan.id == loanId);
    if (found.isEmpty) {
      return const Scaffold(body: Center(child: Text('Loan not found')));
    }
    final s = found.first;
    final l = s.loan;
    final h = st.hideBalances;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.name),
        actions: [
          IconButton(
              tooltip: h ? 'Show balances' : 'Hide balances',
              icon: Icon(h ? Icons.visibility_off : Icons.visibility),
              onPressed: st.toggleHide),
          IconButton(
              tooltip: 'Edit',
              icon: const Icon(Icons.edit),
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => LoanFormPage(edit: l)))),
          IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _delete(context, s)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 40),
        children: [
          LoanCard(summary: s, hidden: h),
          // ── terms ──
          Card(
            elevation: 0,
            color: cs.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(children: [
                _kv('Interest', '${l.rate}% per year'),
                _kv('Tenure', l.tenureText),
                _kv('EMI frequency', l.frequencyText),
                _kv('First EMI date', fmtDate.format(l.startDate)),
                _kv('Number of EMIs', '${l.installments}'),
                _kv('EMI amount', l.emiAmount > 0 ? formatInr(l.emiAmount, hidden: h) : 'Not calculated'),
                _kv('Total interest', s.hasSchedule ? formatInr(s.totalInterest, hidden: h) : '-'),
                _kv('Paid so far', formatInr(s.paidAmount, hidden: h)),
                _kv('Foreclose charges', '${l.foreclosePct}%'),
                _kv('Penalty charges', '${l.penaltyPct}%'),
                if (!l.isClosed)
                  _kv('Foreclosure amount', formatInr(s.foreclosureAmount, hidden: h), bold: true),
                if (l.notes.isNotEmpty) ...[
                  const Divider(),
                  Align(alignment: Alignment.centerLeft, child: SelectableText(l.notes)),
                ],
              ]),
            ),
          ),
          const SizedBox(height: 10),
          // ── actions ──
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.icon(
                onPressed: () => _calculateEmi(context, s),
                icon: const Icon(Icons.calculate),
                label: const Text('Calculate EMI')),
            FilledButton.tonalIcon(
                onPressed: l.isClosed ? null : () => _generate(context, s),
                icon: const Icon(Icons.table_chart_outlined),
                label: Text(s.hasSchedule ? 'Regenerate schedule' : 'Generate EMI schedule')),
            if (!l.isClosed && s.hasSchedule)
              OutlinedButton.icon(
                  onPressed: () => _foreclose(context, s),
                  icon: const Icon(Icons.lock_outline),
                  label: const Text('Foreclose')),
          ]),
          const SizedBox(height: 16),
          Text('EMI schedule', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          if (!s.hasSchedule)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('No EMI entries yet. Tap "Generate EMI schedule".'),
            ),
          for (final e in s.emis) _emiTile(context, s, e, h),
        ],
      ),
    );
  }

  /// One EMI entry card: number, date, status chip, amounts and a menu with
  /// Edit / Mark paid / Create bank transaction.
  Widget _emiTile(BuildContext context, LoanSummary s, LoanEmi e, bool hidden) {
    final cs = Theme.of(context).colorScheme;
    final String label;
    final Color color;
    if (e.isPaid) {
      label = 'Paid ${fmtDate.format(e.paidDate ?? e.dueDate)}';
      color = creditColor(context);
    } else if (e.isCancelled) {
      label = 'Cancelled';
      color = cs.onSurfaceVariant;
    } else if (e.isOverdue) {
      label = 'Overdue';
      color = debitColor(context);
    } else {
      label = 'Pending';
      color = cs.primary;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 2, 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: color.withValues(alpha: .18),
            child: Text('${e.no}',
                style: TextStyle(color: color, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(fmtDate.format(e.dueDate),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                  decoration: BoxDecoration(
                      color: color.withValues(alpha: .15),
                      borderRadius: BorderRadius.circular(10)),
                  child: Text(label, style: TextStyle(fontSize: 11, color: color)),
                ),
                if (e.txnId != null)
                  const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: Icon(Icons.link, size: 16),
                  ),
              ]),
              const SizedBox(height: 4),
              Text(
                'Principal ${formatInr(e.principalPart, hidden: hidden)}  •  Interest ${formatInr(e.interestPart, hidden: hidden)}'
                '${e.penalty > 0 ? '  •  Penalty ${formatInr(e.penalty, hidden: hidden)}' : ''}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ]),
          ),
          const SizedBox(width: 8),
          Text(formatInr(e.emi, hidden: hidden),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'edit') _editEmi(context, e);
              if (v == 'paid') _markPaid(context, s, e);
              if (v == 'unpaid') {
                _run(context, () => _repo.markUnpaid(e.id), done: 'Marked as pending');
              }
              if (v == 'txn') _createTxn(context, s, e);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit date / amount')),
              if (!e.isCancelled)
                e.isPaid
                    ? const PopupMenuItem(value: 'unpaid', child: Text('Mark as not paid'))
                    : const PopupMenuItem(value: 'paid', child: Text('Mark as EMI paid')),
              if (!e.isCancelled)
                PopupMenuItem(
                    value: 'txn',
                    child: Text(e.txnId == null
                        ? 'Create bank transaction'
                        : 'Create another bank transaction')),
            ],
          ),
        ]),
      ),
    );
  }
}
