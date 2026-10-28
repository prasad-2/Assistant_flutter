// Loan summary card (same visual family as the bank account card).
// Header: icon, name, status, OUTSTANDING (right aligned, large).
// Strip:  progress bar + Loan value / EMI / Paid / Next EMI (overlap-proof Wrap).
import 'package:flutter/material.dart';

import '../models/loan_models.dart';
import '../utils/format.dart';
import 'account_avatar.dart';
import 'common.dart';

class LoanCard extends StatelessWidget {
  final LoanSummary summary;
  final bool hidden;
  final VoidCallback? onTap;
  const LoanCard({super.key, required this.summary, required this.hidden, this.onTap});

  @override
  Widget build(BuildContext context) {
    final l = summary.loan;
    final cs = Theme.of(context).colorScheme;
    final base = Color(l.color);
    final backdrop = cs.surfaceContainerHighest;
    final top = Color.alphaBlend(shade(base, .04), backdrop);
    final bottom = Color.alphaBlend(shade(base, -.10), backdrop);
    final fg = onColor(top);
    final outline = base.withValues(alpha: base.a < .6 ? .6 : base.a);

    final next = summary.nextDue;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 3,
        color: cs.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: outline, width: 1.3)),
        child: InkWell(
          onTap: onTap,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // ── header ──
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              decoration: BoxDecoration(
                  gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [top, bottom])),
              child: Column(children: [
                Row(children: [
                  AccountAvatar(iconKey: l.iconKey, blob: l.iconBlob, size: 34),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(l.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: fg, fontWeight: FontWeight.w800, fontSize: 16)),
                  ),
                  if (l.isClosed) _badge('CLOSED', fg) else _badge('LOAN', fg),
                ]),
                const SizedBox(height: 4),
                LayoutBuilder(builder: (context, c) {
                  return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Expanded(
                      child: Text('${l.rate.toStringAsFixed(l.rate % 1 == 0 ? 0 : 2)}% • ${l.tenureText}',
                          style: TextStyle(color: fg.withValues(alpha: .85), fontSize: 12)),
                    ),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: c.maxWidth * .62),
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('Outstanding',
                                style: TextStyle(
                                    color: fg.withValues(alpha: .8), fontSize: 11)),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: Text(formatInr(summary.outstanding, hidden: hidden),
                                  style: TextStyle(
                                      color: fg,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 22)),
                            ),
                          ]),
                    ),
                  ]);
                }),
              ]),
            ),
            // ── progress + metrics ──
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (summary.hasSchedule) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                        value: summary.progress, minHeight: 7),
                  ),
                  const SizedBox(height: 8),
                ],
                LayoutBuilder(builder: (context, c) {
                  final maxW = c.maxWidth;
                  return Wrap(spacing: 18, runSpacing: 6, children: [
                    _metric(context, 'Loan value', formatInr(l.principal, hidden: hidden), maxW),
                    _metric(
                        context,
                        'EMI',
                        l.emiAmount > 0 ? formatInr(l.emiAmount, hidden: hidden) : 'Not calculated',
                        maxW),
                    _metric(
                        context,
                        'Paid',
                        summary.hasSchedule
                            ? '${summary.paidCount} / ${summary.activeCount}'
                            : 'No schedule',
                        maxW),
                    if (next != null)
                      _metric(context, 'Next EMI',
                          '${fmtDate.format(next.dueDate)} • ${formatInr(next.emi, hidden: hidden)}',
                          maxW,
                          color: next.isOverdue ? debitColor(context) : null),
                  ]);
                }),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _metric(BuildContext context, String label, String text, double maxW,
      {Color? color}) {
    final cs = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxW),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(text,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: color ?? cs.onSurface)),
            ),
          ]),
    );
  }

  Widget _badge(String t, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
            border: Border.all(color: fg.withValues(alpha: .8)),
            borderRadius: BorderRadius.circular(8)),
        child: Text(t,
            style: TextStyle(color: fg, fontSize: 9, fontWeight: FontWeight.w700)),
      );
}
