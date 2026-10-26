// Small calculator shown on top of the transaction form.
// "Use value" copies the result into the form's value field.
import 'package:flutter/material.dart';

/// Recursive-descent evaluator for + − × ÷ and parentheses.
///   expr   := term (('+'|'−') term)*
///   term   := factor (('×'|'÷') factor)*
///   factor := '−' factor | '(' expr ')' | number
class _Parser {
  final String s;
  int i = 0;
  _Parser(this.s);

  double parse() {
    final v = _expr();
    if (i != s.length) throw const FormatException('Invalid expression');
    return v;
  }

  double _expr() {
    var v = _term();
    while (i < s.length && (s[i] == '+' || s[i] == '−')) {
      final op = s[i++];
      final r = _term();
      v = op == '+' ? v + r : v - r;
    }
    return v;
  }

  double _term() {
    var v = _factor();
    while (i < s.length && (s[i] == '×' || s[i] == '÷')) {
      final op = s[i++];
      final r = _factor();
      if (op == '÷') {
        if (r == 0) throw const FormatException('Cannot divide by zero');
        v /= r;
      } else {
        v *= r;
      }
    }
    return v;
  }

  double _factor() {
    if (i < s.length && s[i] == '−') {
      i++;
      return -_factor();
    }
    if (i < s.length && s[i] == '(') {
      i++;
      final v = _expr();
      if (i >= s.length || s[i] != ')') throw const FormatException('Missing )');
      i++;
      return v;
    }
    final start = i;
    while (i < s.length && (RegExp(r'[0-9.]').hasMatch(s[i]))) {
      i++;
    }
    if (start == i) throw const FormatException('Invalid expression');
    return double.parse(s.substring(start, i));
  }
}

/// Evaluates [expr]; unmatched "(" are closed and a trailing operator is
/// ignored so the preview works while the user is still typing.
double evaluateExpression(String expr) {
  var e = expr;
  while (e.isNotEmpty && '+−×÷'.contains(e[e.length - 1])) {
    e = e.substring(0, e.length - 1);
  }
  final open = '('.allMatches(e).length - ')'.allMatches(e).length;
  if (open > 0) e += ')' * open;
  if (e.isEmpty) throw const FormatException('Empty');
  final v = _Parser(e).parse();
  if (v.isNaN || v.isInfinite) throw const FormatException('Invalid result');
  return (v * 100).round() / 100; // money has 2 decimals
}

class CalculatorPanel extends StatefulWidget {
  final String initial; // starting expression (e.g. the current value)
  final ValueChanged<double> onUse; // fill the transaction value
  final VoidCallback onClose;
  const CalculatorPanel(
      {super.key,
      this.initial = '',
      required this.onUse,
      required this.onClose});

  @override
  State<CalculatorPanel> createState() => _CalculatorPanelState();
}

class _CalculatorPanelState extends State<CalculatorPanel> {
  late String _expr = widget.initial;

  static const _ops = '+−×÷';

  /// Current result, or null when the expression is incomplete / invalid.
  double? get _result {
    try {
      return evaluateExpression(_expr);
    } catch (_) {
      return null;
    }
  }

  /// Error text shown instead of the result (e.g. division by zero).
  String? get _error {
    if (_expr.isEmpty) return null;
    try {
      evaluateExpression(_expr);
      return null;
    } on FormatException catch (e) {
      return e.message == 'Cannot divide by zero' ? e.message : null;
    } catch (_) {
      return null;
    }
  }

  String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  /// Handles one key press.
  void _key(String k) {
    setState(() {
      if (k == 'C') {
        _expr = '';
      } else if (k == '⌫') {
        if (_expr.isNotEmpty) _expr = _expr.substring(0, _expr.length - 1);
      } else if (k == '=') {
        final r = _result;
        if (r != null) _expr = _fmt(r);
      } else if (_ops.contains(k)) {
        if (_expr.isEmpty) {
          if (k == '−') _expr = k; // allow a leading minus
        } else if (_ops.contains(_expr[_expr.length - 1])) {
          _expr = _expr.substring(0, _expr.length - 1) + k; // replace operator
        } else if (_expr[_expr.length - 1] != '(' || k == '−') {
          _expr += k;
        }
      } else if (k == '.') {
        // only one dot per number
        final lastNum = _expr.split(RegExp(r'[+−×÷()]')).last;
        if (!lastNum.contains('.')) _expr += lastNum.isEmpty ? '0.' : '.';
      } else {
        _expr += k; // digit or parenthesis
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final r = _result;
    final canUse = r != null && r > 0;

    Widget btn(String k, {Color? bg, Color? fg}) => Expanded(
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: SizedBox(
              height: 46,
              child: FilledButton.tonal(
                style: FilledButton.styleFrom(
                  padding: EdgeInsets.zero,
                  backgroundColor: bg ?? cs.surfaceContainerHighest,
                  foregroundColor: fg ?? cs.onSurface,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () => _key(k),
                child: Text(k,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        );

    Widget row(List<Widget> c) => Row(children: c);

    final opBg = cs.secondaryContainer;
    final opFg = cs.onSecondaryContainer;

    return Material(
      elevation: 12,
      color: cs.surface,
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(26)),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Icon(Icons.calculate, color: cs.primary),
              const SizedBox(width: 8),
              Text('Calculator',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close),
                  onPressed: widget.onClose),
            ]),
            // display: expression + live result
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: .6),
                  borderRadius: BorderRadius.circular(16)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  reverse: true,
                  child: Text(_expr.isEmpty ? '0' : _expr,
                      style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w500,
                          color: cs.onSurface)),
                ),
                const SizedBox(height: 4),
                Text(
                  _error ?? (r == null ? ' ' : '= ${r.toStringAsFixed(2)}'),
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: _error != null ? cs.error : cs.primary),
                ),
              ]),
            ),
            const SizedBox(height: 8),
            row([btn('C', bg: cs.errorContainer, fg: cs.onErrorContainer), btn('('), btn(')'), btn('⌫', bg: opBg, fg: opFg)]),
            row([btn('7'), btn('8'), btn('9'), btn('÷', bg: opBg, fg: opFg)]),
            row([btn('4'), btn('5'), btn('6'), btn('×', bg: opBg, fg: opFg)]),
            row([btn('1'), btn('2'), btn('3'), btn('−', bg: opBg, fg: opFg)]),
            row([btn('0'), btn('.'), btn('=', bg: cs.primary, fg: cs.onPrimary), btn('+', bg: opBg, fg: opFg)]),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: canUse ? () => widget.onUse(r) : null,
                icon: const Icon(Icons.input),
                label: Text(canUse
                    ? 'Use ${r.toStringAsFixed(2)} as transaction value'
                    : 'Enter a calculation (result above 0)'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
