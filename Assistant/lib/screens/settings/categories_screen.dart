// Master data: transaction categories (name, credit/deduct type, icon).
//
// Because balances are calculated from transactions, every edit/delete is
// checked first: users are warned about affected transactions, and a change
// that would make a balance negative is blocked.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../db/app_database.dart';
import '../../models/models.dart';
import '../../providers/app_state.dart';
import '../../utils/icons.dart';
import '../../widgets/common.dart';
import '../../widgets/icon_pickers.dart';

class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

  /// Add (c == null) or edit dialog, followed by the impact checks.
  Future<void> _edit(BuildContext context, [Category? c]) async {
    final st = context.read<AppState>();
    final nameC = TextEditingController(text: c?.name ?? '');
    var type = c?.type ?? 'debit';
    var icon = c?.icon ?? 'category';

    final res = await showDialog<Category>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(c == null ? 'Add category' : 'Edit category'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              // icon button -> icon picker
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () async {
                  final k = await pickCategoryIcon(ctx, icon);
                  if (k != null) setS(() => icon = k);
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: Theme.of(ctx).colorScheme.primaryContainer),
                  child: Icon(categoryIconFor(icon), size: 28),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                    controller: nameC,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Category name')),
              ),
            ]),
            const SizedBox(height: 14),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'debit', label: Text('Deduct')),
                ButtonSegment(value: 'credit', label: Text('Credit')),
              ],
              selected: {type},
              onSelectionChanged: (v) => setS(() => type = v.first),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(
                    ctx, Category(id: c?.id, name: nameC.text, type: type, icon: icon)),
                child: const Text('Save')),
          ],
        ),
      ),
    );
    if (res == null || !context.mounted) return;

    final db = AppDatabase.instance;
    try {
      if (res.name.trim().isEmpty) {
        throw ValidationException('Category name is required.');
      }
      if (c != null) {
        final used = await db.categoryUsageCount(c.id!);
        if (used > 0) {
          final typeChanged = c.type != res.type;
          final nameChanged = c.name != res.name.trim();
          // a type change flips existing amounts: dry-run it first
          if (typeChanged) {
            final err = await db.simulateCategoryChange(res);
            if (err != null) throw ValidationException(err);
          }
          if (!context.mounted) return;
          final ok = await confirmDialog(context,
              title: 'Existing transactions affected',
              message: '$used existing transaction(s) use "${c.name}".'
                  '${typeChanged ? '\n\n• Changing the type flips them between credit and deduct, so account balances will be recalculated.' : ''}'
                  '${nameChanged ? '\n\n• They will show the new category name.' : ''}'
                  '\n\nSave anyway?',
              confirmText: 'Save');
          if (!ok) return;
        } else {
          final ok = await confirmDialog(context,
              title: 'Save changes?',
              message: 'No existing transactions use this category.',
              confirmText: 'Save');
          if (!ok) return;
        }
      }
      await db.saveCategory(res);
      await st.refreshFinance();
    } on ValidationException catch (e) {
      if (context.mounted) showErrorDialog(context, e.message);
    }
  }

  /// Used categories cannot be deleted (it would change balances).
  Future<void> _delete(BuildContext context, Category c) async {
    final st = context.read<AppState>();
    final used = await AppDatabase.instance.categoryUsageCount(c.id!);
    if (!context.mounted) return;
    if (used > 0) {
      showErrorDialog(context,
          '"${c.name}" is used by $used existing transaction(s). Deleting it would affect account balances. Edit or delete those transactions first.');
      return;
    }
    final ok = await confirmDialog(context,
        title: 'Delete category?',
        message: 'Delete "${c.name}"?',
        confirmText: 'Delete');
    if (!ok) return;
    try {
      await AppDatabase.instance.deleteCategory(c.id!);
      await st.refreshFinance();
    } on ValidationException catch (e) {
      if (context.mounted) showErrorDialog(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Transaction categories')),
      floatingActionButton: FloatingActionButton(
          onPressed: () => _edit(context), child: const Icon(Icons.add)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 90),
        children: [
          for (final c in s.categories)
            ListTile(
              leading: CircleAvatar(
                backgroundColor: c.isSystem
                    ? Theme.of(context).colorScheme.secondaryContainer
                    : (c.isCredit ? creditColor(context) : debitColor(context))
                        .withValues(alpha: .18),
                child: Icon(categoryIconFor(c.icon),
                    color: c.isSystem
                        ? Theme.of(context).colorScheme.onSecondaryContainer
                        : (c.isCredit ? creditColor(context) : debitColor(context))),
              ),
              title: Text(c.name),
              subtitle: Text(c.typeLabel),
              trailing: c.isSystem
                  ? const Icon(Icons.lock_outline)
                  : Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () => _edit(context, c)),
                      IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _delete(context, c)),
                    ]),
            ),
        ],
      ),
    );
  }
}
