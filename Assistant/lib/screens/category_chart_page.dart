// Charts: money IN and OUT by category for a chosen period.
//
//  * summary (in / out / net + proportion bar)
//  * donut chart for the selected direction (Out or In)
//  * category list with amount and percentage; tap = open those transactions
//
// Internal moves (self transfers and credit bill repayments) are excluded
// because they only move money between your own accounts.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/app_database.dart';
import '../models/models.dart';
import '../providers/app_state.dart';
import '../utils/format.dart';
import '../utils/icons.dart';
import '../widgets/common.dart';
import 'finance/transactions_view.dart';

/// Period choices of the chart.
enum _Period { week, month30, thisMonth, lastMonth, thisYear, custom }

const _palette = <Color>[
  Color(0xFF1E88E5), Color(0xFFE53935), Color(0xFF43A047), Color(0xFFFB8C00),
  Color(0xFF8E24AA), Color(0xFF00ACC1), Color(0xFFD81B60), Color(0xFF7CB342),
  Color(0xFF6D4C41), Color(0xFF3949AB), Color(0xFFFDD835), Color(0xFF546E7A),
];

/// Totals of one category.
class _Slice {
  final int categoryId;
  final String name;
  final String icon;
  final int total; // paise (positive)
  _Slice(this.categoryId, this.name, this.icon, this.total);
}

class CategoryChartPage extends StatefulWidget {
  const CategoryChartPage({super.key});
  @override
  State<CategoryChartPage> createState() => _CategoryChartPageState();
}

class _CategoryChartPageState extends State<CategoryChartPage> {
  _Period _period = _Period.thisMonth;
  DateTimeRange? _custom;
  bool _showOut = true; // true = money out (expenses), false = money in
  bool _includeScheduled = false;
  bool _loading = true;
  List<_Slice> _out = [];
  List<_Slice> _in = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Start / end (inclusive days) of the selected period.
  DateTimeRange get _range {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_period) {
      case _Period.week:
        return DateTimeRange(start: today.subtract(const Duration(days: 6)), end: today);
      case _Period.month30:
        return DateTimeRange(start: today.subtract(const Duration(days: 29)), end: today);
      case _Period.thisMonth:
        return DateTimeRange(start: DateTime(now.year, now.month, 1), end: today);
      case _Period.lastMonth:
        return DateTimeRange(
            start: DateTime(now.year, now.month - 1, 1),
            end: DateTime(now.year, now.month, 0));
      case _Period.thisYear:
        return DateTimeRange(start: DateTime(now.year, 1, 1), end: today);
      case _Period.custom:
        return _custom ?? DateTimeRange(start: today, end: today);
    }
  }

  /// Loads the transactions of the period and groups them by category.
  Future<void> _load() async {
    setState(() => _loading = true);
    final r = _range;
    final list = await AppDatabase.instance.queryTransactions(TxnFilter(
      from: r.start,
      to: r.end,
      status: _includeScheduled ? null : 'actual',
    ));
    final out = <int, _Slice>{};
    final inn = <int, _Slice>{};
    for (final t in list) {
      // skip internal moves between own accounts
      if (t.categoryType == 'transfer' || t.categoryType == 'repayment') continue;
      final map = t.amount < 0 ? out : inn;
      final cur = map[t.categoryId];
      map[t.categoryId] = _Slice(t.categoryId, t.categoryName, t.categoryIcon,
          (cur?.total ?? 0) + t.amount.abs());
    }
    int byTotal(_Slice a, _Slice b) => b.total.compareTo(a.total);
    if (!mounted) return;
    setState(() {
      _out = out.values.toList()..sort(byTotal);
      _in = inn.values.toList()..sort(byTotal);
      _loading = false;
    });
  }

  Future<void> _pickCustom() async {
    final r = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
        initialDateRange: _custom);
    if (r != null) {
      _custom = r;
      _period = _Period.custom;
      _load();
    }
  }

  String _label(_Period p) {
    switch (p) {
      case _Period.week:
        return 'Last 7 days';
      case _Period.month30:
        return 'Last 30 days';
      case _Period.thisMonth:
        return 'This month';
      case _Period.lastMonth:
        return 'Last month';
      case _Period.thisYear:
        return 'This year';
      case _Period.custom:
        return 'Custom';
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = context.watch<AppState>().hideBalances;
    final cs = Theme.of(context).colorScheme;
    final totalOut = _out.fold<int>(0, (a, s) => a + s.total);
    final totalIn = _in.fold<int>(0, (a, s) => a + s.total);
    final slices = _showOut ? _out : _in;
    final total = _showOut ? totalOut : totalIn;
    final r = _range;

    return Scaffold(
      appBar: AppBar(title: const Text('Charts')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
        children: [
          // ── period chips ──
          SizedBox(
            height: 44,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (final p in _Period.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(_label(p)),
                    selected: _period == p,
                    onSelected: (_) {
                      if (p == _Period.custom) {
                        _pickCustom();
                      } else {
                        _period = p;
                        _load();
                      }
                    },
                  ),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Icon(Icons.date_range, size: 16, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Text('${fmtDate.format(r.start)}  –  ${fmtDate.format(r.end)}',
                  style: TextStyle(color: cs.onSurfaceVariant)),
              const Spacer(),
              const Text('Include scheduled', style: TextStyle(fontSize: 12)),
              Switch(
                  value: _includeScheduled,
                  onChanged: (v) {
                    _includeScheduled = v;
                    _load();
                  }),
            ]),
          ),
          // ── in / out summary ──
          Card(
            elevation: 0,
            color: cs.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(children: [
                Row(children: [
                  _sum('Money in', formatInr(totalIn, hidden: h), creditColor(context)),
                  _sum('Money out', formatInr(totalOut, hidden: h), debitColor(context)),
                  _sum(
                      'Net',
                      formatInr((totalIn - totalOut).abs(), hidden: h),
                      totalIn >= totalOut ? creditColor(context) : debitColor(context)),
                ]),
                const SizedBox(height: 10),
                // proportion bar: in (green) vs out (red)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    height: 10,
                    child: (totalIn + totalOut) == 0
                        ? ColoredBox(color: cs.surfaceContainerHighest)
                        : Row(children: [
                            Expanded(flex: math.max(1, totalIn), child: ColoredBox(color: creditColor(context))),
                            Expanded(flex: math.max(1, totalOut), child: ColoredBox(color: debitColor(context))),
                          ]),
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Out (spent)'), icon: Icon(Icons.north_east)),
                ButtonSegment(value: false, label: Text('In (received)'), icon: Icon(Icons.south_west)),
              ],
              selected: {_showOut},
              onSelectionChanged: (v) => setState(() => _showOut = v.first),
            ),
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(
                padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
          else if (slices.isEmpty)
            const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: Text('No transactions in this period')))
          else ...[
            // ── donut chart ──
            Center(
              child: SizedBox(
                width: 230,
                height: 230,
                child: CustomPaint(
                  painter: _DonutPainter(
                      slices.map((s) => s.total.toDouble()).toList(), cs.surface),
                  child: Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_showOut ? 'Total out' : 'Total in',
                          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 44),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(formatInr(total, hidden: h),
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // ── category list ──
            for (var i = 0; i < slices.length; i++) _row(context, slices[i], i, total, h, r),
          ],
        ],
      ),
    );
  }

  Widget _sum(String label, String value, Color color) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: color)),
          ),
        ]),
      );

  /// One category row: colour dot, icon, name, percentage bar and amount.
  Widget _row(BuildContext context, _Slice s, int i, int total, bool hidden, DateTimeRange r) {
    final color = _palette[i % _palette.length];
    final pct = total == 0 ? 0.0 : s.total / total;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => TransactionsPage(
                    title: s.name,
                    initial: TxnFilter(
                        categoryId: s.categoryId,
                        from: r.start,
                        to: r.end,
                        status: _includeScheduled ? null : 'actual')))),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            CircleAvatar(
                radius: 18,
                backgroundColor: color.withValues(alpha: .18),
                child: Icon(categoryIconFor(s.icon), size: 18, color: color)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                      value: pct, minHeight: 6, color: color,
                      backgroundColor: color.withValues(alpha: .15)),
                ),
              ]),
            ),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(formatInr(s.total, hidden: hidden),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
              Text('${(pct * 100).toStringAsFixed(1)}%',
                  style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// Draws a donut: one arc per value, coloured from [_palette].
class _DonutPainter extends CustomPainter {
  final List<double> values;
  final Color gapColor;
  _DonutPainter(this.values, this.gapColor);

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<double>(0, (a, b) => a + b);
    if (total <= 0) return;
    const stroke = 36.0;
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);
    var start = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      final sweep = values[i] / total * 2 * math.pi;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = _palette[i % _palette.length];
      // tiny gap between arcs when there are several
      final gap = values.length > 1 ? 0.012 : 0.0;
      canvas.drawArc(rect, start + gap, math.max(0.001, sweep - gap * 2), false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.values != values || old.gapColor != gapColor;
}
