// "Distribute balance": split an amount of one account (FROM) between several
// other accounts (TO) by percentage, creating one self transfer per target.
//
// Fields on every line are linked:
//   FROM line :  % of the account's AVAILABLE balance  <->  value
//   TO lines  :  % of the FROM value                   <->  value
// Typing a percentage calculates the value and typing a value calculates the
// percentage. The totals of the TO lines must reach 100 % and the FROM value.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../db/app_database.dart';
import '../../models/models.dart';
import '../../providers/app_state.dart';
import '../../utils/format.dart';
import '../../widgets/calculator.dart';
import '../../widgets/common.dart';
import '../../widgets/form_widgets.dart';

/// One "to account" line.
class _Line {
  int? account;
  final pct = TextEditingController();
  final val = TextEditingController();
  void dispose() {
    pct.dispose();
    val.dispose();
  }
}

/// Answer of the "when?" dialog.
class _When {
  final DateTime dateTime;
  final String status;
  const _When(this.dateTime, this.status);
}

class DistributeScreen extends StatefulWidget {
  const DistributeScreen({super.key});
  @override
  State<DistributeScreen> createState() => _DistributeScreenState();
}

class _DistributeScreenState extends State<DistributeScreen> {
  int? _from;
  final _fromPct = TextEditingController();
  final _fromVal = TextEditingController();
  final List<_Line> _lines = [];
  bool _saving = false;

  /// Percentages may differ from 100 by this much because of 2-decimal rounding.
  static const _pctTolerance = 0.05;

  @override
  void dispose() {
    _fromPct.dispose();
    _fromVal.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  // ───────────── numbers ─────────────

  int _available(AppState st) {
    for (final x in st.summaries) {
      if (x.account.id == _from) return x.available;
    }
    return 0;
  }

  int get _fromValue => parsePaise(_fromVal.text) ?? 0;
  double _pct(TextEditingController c) => double.tryParse(c.text.trim()) ?? 0;
  int _val(_Line l) => parsePaise(l.val.text) ?? 0;

  double get _sumPct => _lines.fold(0.0, (s, l) => s + _pct(l.pct));
  int get _sumVal => _lines.fold(0, (s, l) => s + _val(l));

  // ───────────── linked fields ─────────────

  /// FROM %  ->  FROM value (of the available balance), then the TO lines.
  void _fromPctChanged(AppState st) {
    final v = (_available(st) * _pct(_fromPct) / 100).round();
    _fromVal.text = paiseToInput(v);
    _recalcLines();
  }

  /// FROM value  ->  FROM % , then the TO lines.
  void _fromValChanged(AppState st) {
    final av = _available(st);
    _fromPct.text = av > 0 ? (_fromValue / av * 100).toStringAsFixed(2) : '';
    _recalcLines();
  }

  /// The FROM value changed: keep every TO percentage, recalculate values.
  void _recalcLines() {
    for (final l in _lines) {
      if (l.pct.text.trim().isEmpty) continue;
      l.val.text = paiseToInput((_fromValue * _pct(l.pct) / 100).round());
    }
    setState(() {});
  }

  void _linePctChanged(_Line l) {
    l.val.text = paiseToInput((_fromValue * _pct(l.pct) / 100).round());
    setState(() {});
  }

  void _lineValChanged(_Line l) {
    l.pct.text =
        _fromValue > 0 ? (_val(l) / _fromValue * 100).toStringAsFixed(2) : '';
    setState(() {});
  }

  // ───────────── lines ─────────────

  /// Accounts that can still be chosen as a target (not FROM, not used).
  List<Account> _free(AppState st, {int? keep}) {
    final used = {for (final l in _lines) l.account};
    return st.accounts
        .where((a) => a.id != _from && (a.id == keep || !used.contains(a.id)))
        .toList();
  }

  void _addLine(AppState st) {
    final l = _Line();
    // convenience: pre-fill what is still missing to reach 100 %
    final rest = 100 - _sumPct;
    if (rest > _pctTolerance && _fromValue > 0) {
      l.pct.text = rest.toStringAsFixed(2);
      l.val.text = paiseToInput((_fromValue * rest / 100).round());
    }
    setState(() => _lines.add(l));
  }

  void _removeLine(_Line l) {
    setState(() => _lines.remove(l));
    // dispose after the frame: the removed TextFields are still in the tree now
    WidgetsBinding.instance.addPostFrameCallback((_) => l.dispose());
  }

  // ───────────── distribute ─────────────

  /// Asks for the transaction date-time (and actual / scheduled).
  Future<_When?> _askWhen() {
    var dt = DateTime.now();
    var status = 'actual';
    return showDialog<_When>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Transaction date & time'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () async {
                final d = await showDatePicker(
                    context: ctx,
                    initialDate: dt,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100));
                if (d == null || !ctx.mounted) return;
                final t = await showTimePicker(
                    context: ctx, initialTime: TimeOfDay.fromDateTime(dt));
                if (t == null) return;
                setS(() => dt = DateTime(d.year, d.month, d.day, t.hour, t.minute));
              },
              child: InputDecorator(
                decoration: const InputDecoration(
                    labelText: 'Date & time',
                    prefixIcon: Icon(Icons.event),
                    suffixIcon: Icon(Icons.arrow_drop_down)),
                child: Text(fmtDateTime.format(dt)),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'actual', label: Text('Actual')),
                  ButtonSegment(value: 'scheduled', label: Text('Scheduled')),
                ],
                selected: {status},
                onSelectionChanged: (v) => setS(() => status = v.first),
              ),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, _When(dt, status)),
                child: const Text('Distribute')),
          ],
        ),
      ),
    );
  }

  Future<void> _distribute(AppState st) async {
    void fail(String m) => showErrorDialog(context, m);
    final total = _fromValue;
    if (_from == null) return fail('Select the "from" account.');
    if (total <= 0) return fail('Enter the amount to distribute.');
    if (_lines.isEmpty || _lines.any((l) => l.account == null)) {
      return fail('Add at least one "to" account and select an account on every line.');
    }
    if (_lines.any((l) => _val(l) <= 0)) {
      return fail('Enter a percentage or a value for every account.');
    }
    if ((_sumPct - 100).abs() > _pctTolerance) {
      return fail('The percentages must add up to 100 % (now ${_sumPct.toStringAsFixed(2)} %).');
    }

    // Percentages like 33.33 x 3 cannot match to the paise: when the percent
    // total is right, put the few paise of difference on the biggest line.
    final values = [for (final l in _lines) _val(l)];
    final diff = total - values.fold<int>(0, (a, b) => a + b);
    if (diff != 0) {
      if (diff.abs() > _lines.length) {
        return fail('The values must add up to ${formatInr(total)} (now ${formatInr(_sumVal)}).');
      }
      var big = 0;
      for (var i = 1; i < values.length; i++) {
        if (values[i] > values[big]) big = i;
      }
      values[big] += diff;
    }

    final when = await _askWhen();
    if (when == null || !mounted) return;

    final fromAcc = st.accounts.firstWhere((a) => a.id == _from);
    final self = st.categories.firstWhere((c) => c.isTransfer);
    final inputs = <TxnInput>[];
    for (var i = 0; i < _lines.length; i++) {
      final to = st.accounts.firstWhere((a) => a.id == _lines[i].account);
      inputs.add(TxnInput(
        categoryId: self.id!,
        description:
            'Distribution from ${fromAcc.name} to ${to.name} (${_lines[i].pct.text.trim()}%)',
        dateTime: when.dateTime,
        amountPaise: values[i],
        accountId: _from!,
        toAccountId: to.id,
        status: when.status,
      ));
    }

    setState(() => _saving = true);
    try {
      // all transfers are saved together, or none when a balance rule fails
      await AppDatabase.instance.addTransactions(inputs);
      await st.refreshFinance();
      if (mounted) {
        snack(context, '${inputs.length} self transfer${inputs.length == 1 ? '' : 's'} created');
        Navigator.pop(context, true);
      }
    } on ValidationException catch (e) {
      if (mounted) showErrorDialog(context, e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ───────────── UI pieces ─────────────

  Widget _pctField(TextEditingController c, VoidCallback onChanged) => TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (_) => onChanged(),
        decoration: const InputDecoration(labelText: 'Percent', suffixText: '%', isDense: true),
      );

  /// Value field with a small calculator button.
  Widget _valField(TextEditingController c, VoidCallback onChanged) => TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (_) => onChanged(),
        decoration: InputDecoration(
          labelText: 'Value',
          isDense: true,
          suffixIcon: IconButton(
            tooltip: 'Calculator',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
            icon: const Icon(Icons.calculate_outlined, size: 20),
            onPressed: () async {
              FocusScope.of(context).unfocus();
              final p = parsePaise(c.text) ?? 0;
              final v = await showCalculatorDialog(context,
                  initial: p <= 0 ? '' : (p % 100 == 0 ? '${p ~/ 100}' : paiseToInput(p)));
              if (v != null) {
                c.text = v.toStringAsFixed(2);
                onChanged();
              }
            },
          ),
        ),
      );

  DropdownMenuItem<int> _accItem(Account a, List<Account> all) => DropdownMenuItem(
      value: a.id,
      child: Row(children: [
        CircleAvatar(radius: 6, backgroundColor: Color(a.color)),
        const SizedBox(width: 8),
        Expanded(child: Text(accountPath(a, all), overflow: TextOverflow.ellipsis)),
      ]));

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final available = _available(st);
    final sumPct = _sumPct;
    final sumVal = _sumVal;
    final total = _fromValue;
    final pctOk = (sumPct - 100).abs() <= _pctTolerance;
    final valOk = total > 0 && (total - sumVal).abs() <= _lines.length && _lines.isNotEmpty;
    final free = _free(st);

    return Scaffold(
      appBar: AppBar(title: const Text('Distribute balance')),
      body: st.accounts.length < 2
          ? const Center(
              child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('You need at least two bank accounts to distribute a balance.',
                      textAlign: TextAlign.center)))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                const FormBanner(
                  color: Colors.indigo,
                  icon: Icons.call_split,
                  title: 'Split a balance',
                  subtitle: 'Creates one self transfer for every account below',
                ),
                // ── FROM ──
                FormSection(
                  title: 'From account',
                  icon: Icons.call_made,
                  children: [
                    DropdownButtonFormField<int>(
                      value: _from,
                      isExpanded: true,
                      decoration: const InputDecoration(
                          labelText: 'From bank account',
                          prefixIcon: Icon(Icons.account_balance_outlined)),
                      items: [for (final a in st.accounts) _accItem(a, st.accounts)],
                      onChanged: (v) {
                        _from = v;
                        // the new source cannot also be a target
                        for (final l in _lines.where((l) => l.account == v).toList()) {
                          _removeLine(l);
                        }
                        _fromPctChanged(st); // recalculates and rebuilds
                      },
                    ),
                    if (_from != null)
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(
                          flex: 5,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 2, right: 8),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('Available',
                                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(formatInr(available),
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: available < 0 ? debitColor(context) : null)),
                              ),
                            ]),
                          ),
                        ),
                        Expanded(flex: 4, child: _pctField(_fromPct, () => _fromPctChanged(st))),
                        const SizedBox(width: 8),
                        Expanded(flex: 6, child: _valField(_fromVal, () => _fromValChanged(st))),
                      ]),
                    if (_from != null && total > available)
                      Text('More than the available balance (${formatInr(available)}).',
                          style: TextStyle(fontSize: 12, color: debitColor(context))),
                  ],
                ),
                // ── TO ──
                FormSection(
                  title: 'To accounts',
                  icon: Icons.call_received,
                  children: [
                    // totals: must reach 100 % and the FROM value
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest.withValues(alpha: .6),
                          borderRadius: BorderRadius.circular(12)),
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Total percent',
                                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                            Text('${sumPct.toStringAsFixed(2)} %',
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: pctOk ? creditColor(context) : debitColor(context))),
                            Text(pctOk ? 'complete' : '${(100 - sumPct).toStringAsFixed(2)} % to go',
                                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                          ]),
                        ),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Text('Total value',
                                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(formatInr(sumVal),
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: valOk ? creditColor(context) : debitColor(context))),
                            ),
                            Text(valOk ? 'matches' : '${formatInr(total - sumVal)} to go',
                                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                          ]),
                        ),
                      ]),
                    ),
                    for (var i = 0; i < _lines.length; i++) _lineCard(st, i),
                    OutlinedButton.icon(
                      onPressed: (_from == null || total <= 0 || free.isEmpty)
                          ? null
                          : () => _addLine(st),
                      icon: const Icon(Icons.add),
                      label: Text(_from == null || total <= 0
                          ? 'Select the from account and a value first'
                          : free.isEmpty
                              ? 'No more accounts to add'
                              : 'Add account'),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _saving ? null : () => _distribute(st),
                  icon: const Icon(Icons.call_split),
                  label: const Text('Distribute'),
                ),
              ],
            ),
    );
  }

  /// One target line: account dropdown (+ remove) and the % / value fields.
  Widget _lineCard(AppState st, int i) {
    final l = _lines[i];
    final options = _free(st, keep: l.account);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 4, 10),
      decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(14)),
      child: Column(children: [
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<int>(
              value: options.any((a) => a.id == l.account) ? l.account : null,
              isExpanded: true,
              decoration: InputDecoration(
                  labelText: 'To account ${i + 1}', isDense: true),
              items: [for (final a in options) _accItem(a, st.accounts)],
              onChanged: (v) => setState(() => l.account = v),
            ),
          ),
          IconButton(
              tooltip: 'Remove',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _removeLine(l)),
        ]),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Row(children: [
            Expanded(flex: 4, child: _pctField(l.pct, () => _linePctChanged(l))),
            const SizedBox(width: 8),
            Expanded(flex: 6, child: _valField(l.val, () => _lineValChanged(l))),
          ]),
        ),
      ]),
    );
  }
}
