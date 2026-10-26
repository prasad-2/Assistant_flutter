// Todo tab: group filter chips + list of todos, group management sheet.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../db/app_database.dart';
import '../../models/models.dart';
import '../../providers/app_state.dart';
import '../../widgets/common.dart';
import 'todo_form.dart';
import 'todo_tile.dart';

/// Filter value meaning "todos without a group".
const _ungrouped = -2;

class TodoScreen extends StatefulWidget {
  const TodoScreen({super.key});
  @override
  State<TodoScreen> createState() => _TodoScreenState();
}

class _TodoScreenState extends State<TodoScreen> {
  int? _group; // null = all, _ungrouped, or a group id
  bool _showDone = false;

  Future<void> _manageGroups() => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _GroupsSheet());

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    // the selected group may have been deleted meanwhile
    if (_group != null && _group != _ungrouped && !s.groups.any((g) => g.id == _group)) {
      _group = null;
    }
    // apply the "completed" toggle and the group filter
    final list = s.todos.where((t) {
      if (!_showDone && t.isDone) return false;
      if (_group == null) return true;
      if (_group == _ungrouped) return t.groupId == null;
      return t.groupId == _group;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Todo'),
        actions: [
          IconButton(
            tooltip: _showDone ? 'Hide completed' : 'Show completed',
            icon: Icon(_showDone ? Icons.task_alt : Icons.radio_button_unchecked),
            onPressed: () => setState(() => _showDone = !_showDone),
          ),
          IconButton(
              tooltip: 'Manage groups',
              icon: const Icon(Icons.folder_outlined),
              onPressed: _manageGroups),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => const TodoFormPage())),
        child: const Icon(Icons.add),
      ),
      body: Column(children: [
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: [
              _chip('All', _group == null, () => setState(() => _group = null)),
              _chip('Ungrouped', _group == _ungrouped,
                  () => setState(() => _group = _ungrouped)),
              for (final g in s.groups)
                _chip(g.name, _group == g.id, () => setState(() => _group = g.id)),
            ],
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? const Center(child: Text('No todos here'))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 90),
                  children: [for (final t in list) TodoTile(todo: t)],
                ),
        ),
      ]),
    );
  }

  Widget _chip(String label, bool sel, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(label: Text(label), selected: sel, onSelected: (_) => onTap()),
      );
}

/// Bottom sheet to create, rename and delete todo groups.
class _GroupsSheet extends StatelessWidget {
  const _GroupsSheet();

  /// Name dialog used for both "new" (g == null) and "rename".
  Future<void> _edit(BuildContext context, {TodoGroup? g}) async {
    final c = TextEditingController(text: g?.name ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(g == null ? 'New group' : 'Rename group'),
        content: TextField(
            controller: c,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Group name')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text),
              child: const Text('Save')),
        ],
      ),
    );
    if (name == null) return;
    final st = context.read<AppState>();
    try {
      await AppDatabase.instance.saveGroup(name, id: g?.id);
      await st.refreshTodos();
    } on ValidationException catch (e) {
      if (context.mounted) showErrorDialog(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Expanded(
                child: Text('Todo groups',
                    style: Theme.of(context).textTheme.titleLarge)),
            FilledButton.icon(
                onPressed: () => _edit(context),
                icon: const Icon(Icons.add),
                label: const Text('New')),
          ]),
          const SizedBox(height: 8),
          if (s.groups.isEmpty)
            const Padding(padding: EdgeInsets.all(20), child: Text('No groups yet'))
          else
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (final g in s.groups)
                  ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(g.name),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () => _edit(context, g: g)),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          final ok = await confirmDialog(context,
                              title: 'Delete group?',
                              message:
                                  'Todos in "${g.name}" will be kept but become ungrouped.',
                              confirmText: 'Delete');
                          if (!ok) return;
                          await AppDatabase.instance.deleteGroup(g.id!);
                          await s.refreshTodos();
                        },
                      ),
                    ]),
                  ),
              ]),
            ),
        ]),
      ),
    );
  }
}
