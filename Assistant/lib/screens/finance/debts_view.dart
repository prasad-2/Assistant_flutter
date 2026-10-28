// "Debts" tab (Splitwise-like): overall summary + one card per person.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../db/debt_repository.dart';
import '../../models/debt_models.dart';
import '../../models/models.dart';
import '../../providers/app_state.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';
import 'debt_entry_form.dart';
import 'debt_person_page.dart';

/// Actions used by the Debts tab and by the Finance "Add" button.
class DebtActions {
  /// Asks for a name and creates the person. Returns the new id (or null).
  static Future<int?> addPerson(BuildContext context, {String? initial, int? id}) async {
    final c = TextEditingController(text: initial ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(id == null ? 'Add person' : 'Rename person'),
        content: TextField(
            controller: c,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
                labelText: 'Name', prefixIcon: Icon(Icons.person_outline))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Save')),
        ],
      ),
    );
    if (name == null || !context.mounted) return null;
    final st = context.read<AppState>();
    try {
      final r = await DebtRepository.instance.savePerson(name, id: id);
      await st.refreshFinance();
      return r;
    } on ValidationException catch (e) {
      if (context.mounted) showErrorDialog(context, e.message);
      return null;
    }
  }

  /// Opens the add-entry form (optionally for a fixed person).
  static Future<void> addEntry(BuildContext context, {int? personId}) =>
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => DebtEntryFormPage(personId: personId)));
}

class DebtsView extends StatelessWidget {
  const DebtsView({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final h = s.hideBalances;
    final owedToMe = s.people.where((p) => p.net > 0).fold<int>(0, (a, p) => a + p.net);
    final iOwe = s.people.where((p) => p.net < 0).fold<int>(0, (a, p) => a - p.net);
    final net = owedToMe - iOwe;

    if (s.people.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
              'No debts tracked yet.\nTap "Add" to add a friend and record what you lent or borrowed.',
              textAlign: TextAlign.center),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
      children: [
        // overall summary
        Card(
          elevation: 0,
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              _sum(context, 'You are owed', formatInr(owedToMe, hidden: h), creditColor(context)),
              _sum(context, 'You owe', formatInr(iOwe, hidden: h), debitColor(context)),
              _sum(context, 'Net', formatInr(net.abs(), hidden: h),
                  net == 0 ? null : (net > 0 ? creditColor(context) : debitColor(context))),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        for (final p in s.people) _personCard(context, p, h),
      ],
    );
  }

  Widget _sum(BuildContext context, String label, String value, Color? color) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: color)),
          ),
        ]),
      );

  Widget _personCard(BuildContext context, DebtPerson p, bool hidden) {
    final cs = Theme.of(context).colorScheme;
    final Color? c = p.settled ? null : (p.owesMe ? creditColor(context) : debitColor(context));
    final status = p.settled
        ? 'All settled up'
        : p.owesMe
            ? 'owes you'
            : 'you owe';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => DebtPersonPage(personId: p.id))),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            CircleAvatar(
              backgroundColor: cs.primaryContainer,
              child: Text(p.name.isEmpty ? '?' : p.name[0].toUpperCase(),
                  style: TextStyle(color: cs.onPrimaryContainer, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                Text('${p.entries} entr${p.entries == 1 ? 'y' : 'ies'}',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ]),
            ),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 170),
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(status, style: TextStyle(fontSize: 12, color: c ?? cs.onSurfaceVariant)),
                if (!p.settled)
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(formatInr(p.net.abs(), hidden: hidden),
                        style: TextStyle(fontSize: 19, fontWeight: FontWeight.w500, color: c)),
                  ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
