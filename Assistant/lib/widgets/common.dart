// Small reusable helpers: dialogs, snackbars, colour helpers, account paths.
import 'package:flutter/material.dart';

import '../models/models.dart';

/// Black or white text, whichever is readable on [bg].
Color onColor(Color bg) =>
    ThemeData.estimateBrightnessForColor(bg) == Brightness.dark
        ? Colors.white
        : Colors.black87;

/// Slightly lighter (amount > 0) or darker (amount < 0) version of [c];
/// keeps the alpha so transparent colours stay transparent.
Color shade(Color c, double amount) {
  final hsl = HSLColor.fromColor(c);
  return hsl
      .withLightness((hsl.lightness + amount).clamp(0.0, 1.0))
      .toColor();
}

/// Yes/No dialog. Returns true only when the user confirms.
Future<bool> confirmDialog(BuildContext context,
    {required String title,
    required String message,
    String confirmText = 'Confirm'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmText)),
      ],
    ),
  );
  return r == true;
}

/// Shows a validation / error message the user has to acknowledge.
Future<void> showErrorDialog(BuildContext context, String message,
    {String title = 'Cannot proceed'}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
      title: Text(title),
      content: Text(message),
      actions: [
        FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))
      ],
    ),
  );
}

void snack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

/// "Parent › Child › Grandchild" label for nested accounts.
String accountPath(Account a, List<Account> all) {
  final byId = {for (final x in all) x.id!: x};
  final parts = <String>[a.name];
  var cur = a.parentId;
  var guard = 0; // protects against bad data (cycles)
  while (cur != null && byId.containsKey(cur) && guard++ < 50) {
    parts.insert(0, byId[cur]!.name);
    cur = byId[cur]!.parentId;
  }
  return parts.join(' › ');
}

/// Ids of all accounts below [id] (children, grandchildren, ...).
Set<int> descendantsOf(int id, List<Account> all) {
  final out = <int>{};
  void walk(int p) {
    for (final a in all) {
      if (a.parentId == p && out.add(a.id!)) walk(a.id!);
    }
  }

  walk(id);
  return out;
}

/// Green for credits, red for debits (used instead of +/- prefixes).
Color creditColor(BuildContext c) => Theme.of(c).brightness == Brightness.dark
    ? Colors.greenAccent.shade400
    : Colors.green.shade700;
Color debitColor(BuildContext c) => Theme.of(c).brightness == Brightness.dark
    ? Colors.redAccent.shade200
    : Colors.red.shade700;
