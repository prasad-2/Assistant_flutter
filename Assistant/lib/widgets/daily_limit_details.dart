// Popup of the "Day-start limit" on the Home screen.
//
// Shows how the day-start daily limit is calculated right now (the balances
// saved at 12 am) next to a RECALCULATION that uses transaction dates, and
// lets the user reset the limit to the recalculated value.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../utils/format.dart';
import 'common.dart';

Future<void> showDailyLimitDetails(BuildContext context, {required bool hidden}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _DailyLimitSheet(hidden: hidden),
  );
}

class _DailyLimitSheet extends StatefulWidget {
  final bool hidden;
  const _DailyLimitSheet({required this.hidden});
  @override
  State<_DailyLimitSheet> createState() => _DailyLimitSheetState();
}

class _DailyLimitSheetState extends State<_DailyLimitSheet> {
  List<DayStartLine>? _lines;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    context.read<AppState>().dayStartLines().then((l) {
      if (mounted) setState(() => _lines = l);
    });
  }

  String _m(int v) => formatInr(v, hidden: widget.hidden);

  Color? _sign(int v) {
    if (widget.hidden || v == 0) return null;
    return v > 0 ? creditColor(context) : debitColor(context);
  }

  /// label ... amount line
  Widget _line(String label, int value,
      {String op = '', bool total = false, String? note, Color? color}) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
            width: 22,
            child: Text(op,
                style: TextStyle(fontWeight: FontWeight.w700, color: cs.onSurfaceVariant))),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: TextStyle(fontWeight: total ? FontWeight.w700 : FontWeight.w400)),
            if (note != null)
              Text(note, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          ]),
        ),
        const SizedBox(width: 8),
        Text(_m(value),
            style: TextStyle(
                fontSize: total ? 17 : 14,
                fontWeight: total ? FontWeight.w700 : FontWeight.w500,
                color: color ?? _sign(value))),
      ]),
    );
  }

  Widget _heading(String t) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 4),
        child: Text(t,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
      );

  Future<void> _apply() async {
    setState(() => _busy = true);
    await context.read<AppState>().applyDayStart(_lines!);
    if (!mounted) return;
    Navigator.pop(context);
    snack(context, 'Daily limit recalculated and reset');
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final days = s.daysLeftInMonth;
    final lines = _lines;
    final savedTotal = lines?.fold<int>(0, (a, l) => a + l.saved) ?? 0;
    final newTotal = lines?.fold<int>(0, (a, l) => a + l.recalculated) ?? 0;
    final savedLimit = (savedTotal / days).round();
    final newLimit = (newTotal / days).round();
    final changed = lines != null && newTotal != savedTotal;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .8,
      maxChildSize: .95,
      builder: (context, scroll) => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Row(children: [
            const Icon(Icons.speed),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Day-start daily limit',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                Text('How it is calculated',
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ]),
            ),
            Text('${_m(savedLimit)} / day',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w600, color: _sign(savedLimit))),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: lines == null
              ? const Center(child: CircularProgressIndicator())
              : lines.isEmpty
                  ? const Center(child: Text('No regular accounts selected'))
                  : ListView(
                      controller: scroll,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      children: [
                        _heading('Current calculation (saved at 12 am)'),
                        for (final l in lines)
                          _line(l.account.name, l.saved, op: '+',
                              note: 'available balance at the start of the day'),
                        const Divider(),
                        _line('Start-of-day available', savedTotal, op: '=', total: true),
                        // plain number of days (not an amount)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(children: [
                            const SizedBox(
                                width: 22,
                                child: Text('÷',
                                    style: TextStyle(fontWeight: FontWeight.w700))),
                            const Expanded(
                                child: Text('Days left this month (today included)')),
                            Text('$days',
                                style: const TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w500)),
                          ]),
                        ),
                        const Divider(),
                        _line('Day-start limit per day', savedLimit,
                            op: '=', total: true),
                        _heading('Recalculated using transaction dates'),
                        for (final l in lines)
                          _line(l.account.name, l.recalculated, op: '+',
                              note: l.recalculated == l.saved
                                  ? 'same as saved'
                                  : 'was ${_m(l.saved)}'),
                        const Divider(),
                        _line('Start-of-day available', newTotal, op: '=', total: true),
                        _line('New limit per day  (÷ $days days)', newLimit,
                            op: '=', total: true),
                        if (changed)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                                'The limit changes by ${_m((newLimit - savedLimit).abs())} per day '
                                '(${newLimit > savedLimit ? 'higher' : 'lower'}).',
                                style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: newLimit > savedLimit
                                        ? creditColor(context)
                                        : debitColor(context))),
                          )
                        else
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text('Nothing to change: the saved limit is already up to date.'),
                          ),
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                              'Rule: balance at 12:00 am today = actual transactions DATED before today (even if you added them later) minus scheduled debits (blocked money), plus the credit limit for credit accounts. Transactions dated today are today\'s movements and are not included.',
                              style: Theme.of(context).textTheme.bodySmall),
                        ),
                      ],
                    ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(
                child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'))),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: (lines == null || lines.isEmpty || _busy) ? null : _apply,
                icon: const Icon(Icons.restart_alt),
                label: const Text('Recalculate & reset'),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}
