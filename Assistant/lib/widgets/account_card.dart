// The bank account card used in the Finance tab (regular size) and on the
// Home screen (compact size).
//
// Layout (top to bottom):
//   1. coloured header – icon, name, badges, expand/collapse arrow, menu, and
//                        on the second line: owner (left) and the AVAILABLE
//                        balance (right-aligned, large)
//   2. metrics strip   – Actual / Scheduled (+ Credit limit / Total spend)
//
// Metrics live in a Wrap and every value is scaled down to the available
// width, so very large amounts can never overlap each other.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../utils/format.dart';
import 'account_avatar.dart';
import 'account_breakdown.dart';
import 'common.dart';

enum AccountCardSize { regular, compact }

class AccountCard extends StatelessWidget {
  final AccountSummary summary;
  final bool hidden; // mask balances
  final AccountCardSize size;
  final bool showIndent; // indent child accounts (Finance tab only)
  final VoidCallback? onTap;
  final VoidCallback? onEdit; // when null the popup menu is not shown
  final VoidCallback? onDelete;
  final VoidCallback? onToggleRegular;

  /// Parent accounts show an arrow when [onToggleExpand] is given.
  final bool expanded;
  final VoidCallback? onToggleExpand;

  /// Individual show/hide button (eye) in the header; hidden when null.
  final VoidCallback? onToggleHidden;

  /// Reorder mode: up / down arrows replace the menu. A null callback means
  /// "cannot move further in that direction" (arrow is disabled).
  final bool reorderMode;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  const AccountCard({
    super.key,
    required this.summary,
    required this.hidden,
    this.size = AccountCardSize.regular,
    this.showIndent = true,
    this.onTap,
    this.onEdit,
    this.onDelete,
    this.onToggleRegular,
    this.expanded = true,
    this.onToggleExpand,
    this.onToggleHidden,
    this.reorderMode = false,
    this.onMoveUp,
    this.onMoveDown,
  });

  bool get _compact => size == AccountCardSize.compact;

  @override
  Widget build(BuildContext context) {
    final a = summary.account;
    final cs = Theme.of(context).colorScheme;

    // The user can choose a transparent colour, so the header colour is
    // composited over a neutral "backdrop" that is lighter than the app
    // background in dark mode. This keeps the card visibly separate from the
    // page (no blending into the dark background).
    final base = Color(a.color);
    final backdrop = cs.surfaceContainerHighest;
    final top = Color.alphaBlend(shade(base, .04), backdrop);
    final bottom = Color.alphaBlend(shade(base, -.10), backdrop);
    final fg = onColor(top);
    // outline in the account colour (never fainter than 60 %)
    final outline = base.withValues(alpha: base.a < .6 ? .6 : base.a);

    return Padding(
      padding: EdgeInsets.only(
        left: showIndent ? summary.depth * 14.0 : 0,
        bottom: _compact ? 6 : 8,
      ),
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
            _header(context, a, top, bottom, fg),
            _metrics(context, a),
          ]),
        ),
      ),
    );
  }

  /// Coloured top part: identity row + (owner | available balance) row.
  Widget _header(
      BuildContext context, Account a, Color top, Color bottom, Color fg) {
    final hasMenu = onEdit != null && !reorderMode;
    final canToggle =
        summary.hasChildren && onToggleExpand != null && !reorderMode;

    return Container(
      padding: EdgeInsets.fromLTRB(_compact ? 10 : 12, _compact ? 6 : 8,
          hasMenu ? 2 : 10, _compact ? 6 : 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [top, bottom]),
      ),
      child: Column(children: [
        // row 1: icon, name, badges, expand arrow, menu
        Row(children: [
          AccountAvatar(
              iconKey: a.iconKey, blob: a.iconBlob, size: _compact ? 28 : 36),
          const SizedBox(width: 10),
          Expanded(
            child: Text(a.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: fg,
                    fontWeight: FontWeight.w800,
                    fontSize: _compact ? 14 : 16)),
          ),
          if (a.isCredit) _badge('CREDIT', fg),
          if (a.isRegular)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Icon(Icons.star_rounded, size: 18, color: fg),
            ),
          // eye: show / hide the values of THIS card only
          if (onToggleHidden != null && !reorderMode)
            IconButton(
              tooltip: hidden ? 'Show values' : 'Hide values',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
              icon: Icon(hidden ? Icons.visibility_off : Icons.visibility,
                  color: fg, size: 20),
              onPressed: onToggleHidden,
            ),
          // expand / collapse the child accounts (nested)
          if (canToggle)
            IconButton(
              tooltip: expanded ? 'Collapse child accounts' : 'Expand child accounts',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
              icon: Icon(expanded ? Icons.expand_less : Icons.expand_more,
                  color: fg, size: 24),
              onPressed: onToggleExpand,
            ),
          // reorder mode: move the card up / down (saved automatically)
          if (reorderMode) ...[
            IconButton(
              tooltip: 'Move up',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
              icon: Icon(Icons.arrow_upward, color: fg.withValues(alpha: onMoveUp == null ? .3 : 1)),
              onPressed: onMoveUp,
            ),
            IconButton(
              tooltip: 'Move down',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
              icon: Icon(Icons.arrow_downward, color: fg.withValues(alpha: onMoveDown == null ? .3 : 1)),
              onPressed: onMoveDown,
            ),
          ],
          if (hasMenu)
            PopupMenuButton<String>(
              iconColor: fg,
              padding: EdgeInsets.zero,
              iconSize: 20,
              onSelected: (v) {
                if (v == 'edit') onEdit?.call();
                if (v == 'delete') onDelete?.call();
                if (v == 'regular') onToggleRegular?.call();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(
                    value: 'regular',
                    child: Text(
                        a.isRegular ? 'Remove from regular' : 'Mark as regular')),
                const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
        ]),
        SizedBox(height: _compact ? 2 : 4),
        // row 2: owner (left) and AVAILABLE balance (right aligned, larger)
        LayoutBuilder(builder: (context, c) {
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: Text(
                  a.owner +
                      (summary.parentName != null ? '  •  ${summary.parentName}' : ''),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: fg.withValues(alpha: .85),
                      fontSize: _compact ? 11 : 12),
                ),
              ),
              const SizedBox(width: 8),
              // the value never takes more than ~62 % of the width
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => _explain(context, BreakdownKind.available),
                child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: c.maxWidth * .62),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Available',
                        style: TextStyle(
                            color: fg.withValues(alpha: .8),
                            fontSize: _compact ? 10 : 11)),
                    // Negative available balance (scheduled debits can cause
                    // this): shown in RED on a light pill so it is readable on
                    // any card colour. Positive keeps the normal header colour.
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: summary.available < 0 && !hidden
                          ? Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 1),
                              decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: .92),
                                  borderRadius: BorderRadius.circular(10)),
                              child: Text(
                                  formatInr(summary.available, hidden: hidden),
                                  style: TextStyle(
                                      color: Colors.red.shade700,
                                      fontWeight: FontWeight.w500,
                                      fontSize: _compact ? 17 : 22)),
                            )
                          : Text(formatInr(summary.available, hidden: hidden),
                              style: TextStyle(
                                  color: fg,
                                  fontWeight: FontWeight.w500,
                                  fontSize: _compact ? 17 : 22)),
                    ),
                  ],
                ),
              ),
              ), // InkWell (tap = explain Available)
            ]),
          );
        }),
      ]),
    );
  }

  /// green for positive, red for negative, neutral for zero or hidden values
  Color? _sign(BuildContext context, int v) {
    if (hidden || v == 0) return null;
    return v > 0 ? creditColor(context) : debitColor(context);
  }

  /// Opens the "how is this calculated" popup for the tapped value.
  void _explain(BuildContext context, BreakdownKind kind) {
    if (reorderMode) return;
    showAccountBreakdown(context, summary, kind, hidden: hidden);
  }

  /// Bottom strip, ONE row of four equal columns so the card does not grow:
  ///   Actual | Scheduled in | Scheduled out | Summary
  /// Summary = actual + scheduled in - scheduled out (the projected total).
  /// Credit accounts get a second row: credit limit and total spend.
  /// Colours: positive = green, negative = red. "Scheduled out" is money
  /// leaving, so it is red. Tapping a value explains its calculation.
  Widget _metrics(BuildContext context, Account a) {
    final inn = summary.scheduledIn;
    final out = summary.scheduledOut;
    final projected = summary.actual + inn - out;

    // credit account: total spend = credit limit - ACTUAL value
    // (scheduled entries are deliberately ignored here)
    final totalSpend = math.max(0, a.creditLimit - summary.actual);

    return Padding(
      padding: EdgeInsets.fromLTRB(
          _compact ? 10 : 12, _compact ? 6 : 8, 6, _compact ? 7 : 10),
      child: Column(children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _cell(context, 'Actual', formatInr(summary.actual, hidden: hidden),
              color: _sign(context, summary.actual),
              onTap: () => _explain(context, BreakdownKind.actual)),
          _cell(context, 'Scheduled in', formatInr(inn, hidden: hidden),
              color: _sign(context, inn),
              onTap: () => _explain(context, BreakdownKind.scheduledIn)),
          _cell(context, 'Scheduled out', formatInr(out, hidden: hidden),
              color: (!hidden && out > 0) ? debitColor(context) : null,
              onTap: () => _explain(context, BreakdownKind.scheduledOut)),
          _cell(context, 'Summary', formatInr(projected, hidden: hidden),
              color: _sign(context, projected),
              onTap: () => _explain(context, BreakdownKind.summary)),
        ]),
        if (a.isCredit) ...[
          SizedBox(height: _compact ? 4 : 6),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _cell(context, 'Credit limit', formatInr(a.creditLimit, hidden: hidden)),
            _cell(context, 'Total spend', formatInr(totalSpend, hidden: hidden),
                color: (!hidden && totalSpend > 0) ? debitColor(context) : null,
                onTap: () => _explain(context, BreakdownKind.totalSpend)),
            const Spacer(flex: 2),
          ]),
        ],
      ]),
    );
  }

  /// One equal-width column: small label above a value that scales down.
  /// When [onTap] is given the whole column is tappable.
  Widget _cell(BuildContext context, String label, String text,
      {Color? color, VoidCallback? onTap}) {
    final cs = Theme.of(context).colorScheme;
    final fs = _compact ? 12.0 : 13.5;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(right: 6, top: 2, bottom: 2),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: _compact ? 9.5 : 10.5, color: cs.onSurfaceVariant)),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(text,
                  style: TextStyle(
                      fontSize: fs,
                      fontWeight: FontWeight.w500,
                      color: color ?? cs.onSurface)),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _badge(String t, Color fg) => Container(
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
            border: Border.all(color: fg.withValues(alpha: .8)),
            borderRadius: BorderRadius.circular(8)),
        child: Text(t,
            style: TextStyle(color: fg, fontSize: 9, fontWeight: FontWeight.w700)),
      );
}
