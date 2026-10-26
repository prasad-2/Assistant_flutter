// Account operations shared by the Finance list and the account detail page
// (so the confirm / validate / refresh logic exists only once).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../db/app_database.dart';
import '../../models/models.dart';
import '../../providers/app_state.dart';
import '../../widgets/common.dart';
import 'account_form.dart';

class AccountActions {
  /// Opens the add (a == null) or edit form.
  static Future<void> openForm(BuildContext context, [Account? a]) =>
      Navigator.push(
          context, MaterialPageRoute(builder: (_) => AccountFormPage(edit: a)));

  /// Flips the "regular account" flag and refreshes the lists.
  static Future<void> toggleRegular(BuildContext context, Account a) async {
    final st = context.read<AppState>();
    await AppDatabase.instance.setRegular(a.id!, !a.isRegular);
    await st.refreshFinance();
  }

  /// Confirms, then deletes. Validation errors (children, linked transfers...)
  /// are shown to the user. Returns true when the account was deleted.
  static Future<bool> confirmAndDelete(BuildContext context, Account a) async {
    final st = context.read<AppState>();
    final n = await AppDatabase.instance.accountTxnCount(a.id!);
    if (!context.mounted) return false;
    final ok = await confirmDialog(context,
        title: 'Delete account?',
        message:
            'Delete "${a.name}"${n > 0 ? ' and its $n transaction(s)' : ''}? This cannot be undone.',
        confirmText: 'Delete');
    if (!ok) return false;
    try {
      await AppDatabase.instance.deleteAccount(a.id!);
      await st.refreshFinance();
      if (context.mounted) snack(context, 'Account deleted');
      return true;
    } on ValidationException catch (e) {
      if (context.mounted) showErrorDialog(context, e.message);
      return false;
    }
  }
}
