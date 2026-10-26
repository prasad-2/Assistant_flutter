// One todo row: checkbox, title, notes, group/due date and a popup menu.
// Used by the Todo tab and the Home screen.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../providers/app_state.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';
import 'todo_form.dart';

class TodoTile extends StatelessWidget {
  final Todo todo;
  const TodoTile({super.key, required this.todo});

  @override
  Widget build(BuildContext context) {
    final st = context.read<AppState>();
    final cs = Theme.of(context).colorScheme;
    // "Group • 25-Oct-26 18:30"
    final sub = <String>[
      if (todo.groupName != null) todo.groupName!,
      if (todo.dueAt != null) fmtDateTime.format(todo.dueAt!),
    ].join('  •  ');
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        leading: Checkbox(
          value: todo.isDone,
          onChanged: (v) => st.setTodoDone(todo, v ?? false),
        ),
        title: Text(todo.title,
            style: TextStyle(
                decoration: todo.isDone ? TextDecoration.lineThrough : null)),
        subtitle: (sub.isEmpty && todo.notes.isEmpty)
            ? null
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (todo.notes.isNotEmpty)
                  Text(todo.notes, maxLines: 2, overflow: TextOverflow.ellipsis),
                if (sub.isNotEmpty)
                  Row(children: [
                    Flexible(
                      child: Text(sub,
                          style: TextStyle(color: todo.isOverdue ? cs.error : null)),
                    ),
                    if (todo.reminder && !todo.isDone)
                      const Padding(
                        padding: EdgeInsets.only(left: 6),
                        child: Icon(Icons.alarm, size: 16),
                      ),
                  ]),
              ]),
        trailing: PopupMenuButton<String>(
          onSelected: (v) async {
            if (v == 'edit') {
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => TodoFormPage(edit: todo)));
            } else if (v == 'done') {
              st.setTodoDone(todo, !todo.isDone);
            } else if (v == 'delete') {
              final ok = await confirmDialog(context,
                  title: 'Delete todo?',
                  message: 'Delete "${todo.title}"?',
                  confirmText: 'Delete');
              if (ok) await st.deleteTodo(todo);
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
                value: 'done',
                child: Text(todo.isDone ? 'Mark as pending' : 'Mark as completed')),
            const PopupMenuItem(value: 'edit', child: Text('Edit')),
            const PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
      ),
    );
  }
}
