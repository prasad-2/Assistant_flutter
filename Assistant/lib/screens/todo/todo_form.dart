// Add / edit todo form (title, notes, group, due date-time, alarm reminder).
// Also shown inside the quick-add dialog of the home-screen widget.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../db/app_database.dart';
import '../../models/models.dart';
import '../../providers/app_state.dart';
import '../../services/notification_service.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';
import '../../widgets/form_widgets.dart';

/// Special dropdown value meaning "create a new group".
const _newGroup = -1;

class TodoFormPage extends StatefulWidget {
  final Todo? edit; // null = add
  const TodoFormPage({super.key, this.edit});
  @override
  State<TodoFormPage> createState() => _TodoFormPageState();
}

class _TodoFormPageState extends State<TodoFormPage> {
  final _key = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.edit?.title ?? '');
  late final _notes = TextEditingController(text: widget.edit?.notes ?? '');
  late int? _group = widget.edit?.groupId;
  late DateTime? _due = widget.edit?.dueAt;
  late bool _reminder = widget.edit?.reminder ?? false;
  late int _offset = widget.edit?.reminderOffsetMin ?? 0;

  /// Reminder lead times: minutes before the due time -> label.
  static const _offsets = {
    0: 'At due time',
    5: '5 minutes before',
    15: '15 minutes before',
    30: '30 minutes before',
    60: '1 hour before',
    1440: '1 day before',
  };

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  /// Date picker followed by time picker.
  Future<void> _pickDue() async {
    final d = await showDatePicker(
        context: context,
        initialDate: _due ?? DateTime.now(),
        firstDate: DateTime(2000),
        lastDate: DateTime(2100));
    if (d == null || !mounted) return;
    final t = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_due ?? DateTime.now()));
    if (t == null) return;
    setState(() => _due = DateTime(d.year, d.month, d.day, t.hour, t.minute));
  }

  /// Asks for a name, creates the group and selects it.
  Future<void> _addGroup() async {
    final c = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New group'),
        content: TextField(
            controller: c,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Group name')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text),
              child: const Text('Add')),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    final st = context.read<AppState>();
    try {
      final id = await AppDatabase.instance.saveGroup(name);
      await st.refreshTodos();
      setState(() => _group = id);
    } on ValidationException catch (e) {
      if (mounted) showErrorDialog(context, e.message);
    }
  }

  /// Validates, checks the reminder time and saves (which also schedules the alarm).
  Future<void> _save() async {
    if (!_key.currentState!.validate()) return;
    if (_reminder) {
      if (_due == null) {
        showErrorDialog(context, 'Set a due date & time to use a reminder.');
        return;
      }
      final at = _due!.subtract(Duration(minutes: _offset));
      if (!at.isAfter(DateTime.now())) {
        showErrorDialog(context, 'The reminder time is already in the past.');
        return;
      }
      // exact alarms need a special permission; ask now (a user action)
      await NotificationService.instance.askExactAlarmPermissionIfNeeded();
    }
    if (!mounted) return;
    final st = context.read<AppState>();
    final t = Todo(
      id: widget.edit?.id,
      title: _title.text,
      notes: _notes.text,
      groupId: _group,
      dueAt: _due,
      reminder: _reminder && _due != null,
      reminderOffsetMin: _offset,
      isDone: widget.edit?.isDone ?? false,
      completedAt: widget.edit?.completedAt,
    );
    try {
      await st.saveTodo(t);
      if (mounted) Navigator.pop(context, true);
    } on ValidationException catch (e) {
      if (mounted) showErrorDialog(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    if (_group != null && !st.groups.any((g) => g.id == _group)) _group = null;
    return Scaffold(
      appBar: AppBar(title: Text(widget.edit == null ? 'Add todo' : 'Edit todo')),
      body: Form(
        key: _key,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            // banner: summary of the todo being created
            FormBanner(
              color: cs.primary,
              icon: _reminder ? Icons.alarm_on : Icons.checklist_rounded,
              title: _title.text.trim().isEmpty ? 'New todo' : _title.text.trim(),
              subtitle: _due == null
                  ? 'No due date'
                  : 'Due ${fmtDateTime.format(_due!)}${_reminder ? '  •  alarm on' : ''}',
            ),
            FormSection(
              title: 'Task',
              icon: Icons.edit_note,
              children: [
                TextFormField(
                  controller: _title,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => setState(() {}), // refresh banner
                  decoration: const InputDecoration(
                      labelText: 'Title', prefixIcon: Icon(Icons.title)),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                TextFormField(
                  controller: _notes,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                      labelText: 'Notes (optional)',
                      alignLabelWithHint: true,
                      prefixIcon: Icon(Icons.notes)),
                ),
                DropdownButtonFormField<int?>(
                  value: _group,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: 'Group', prefixIcon: Icon(Icons.folder_outlined)),
                  items: [
                    const DropdownMenuItem<int?>(
                        value: null, child: Text('No group')),
                    for (final g in st.groups)
                      DropdownMenuItem<int?>(value: g.id, child: Text(g.name)),
                    const DropdownMenuItem<int?>(
                        value: _newGroup, child: Text('➕  New group…')),
                  ],
                  onChanged: (v) {
                    if (v == _newGroup) {
                      _addGroup();
                    } else {
                      setState(() => _group = v);
                    }
                  },
                ),
              ],
            ),
            FormSection(
              title: 'Schedule & reminder',
              icon: Icons.schedule,
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _pickDue,
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Due date & time (optional)',
                      prefixIcon: const Icon(Icons.event),
                      suffixIcon: _due == null
                          ? const Icon(Icons.arrow_drop_down)
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () => setState(() {
                                _due = null;
                                _reminder = false;
                              }),
                            ),
                    ),
                    child: Text(_due == null ? 'Not set' : fmtDateTime.format(_due!)),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.alarm),
                  title: const Text('Reminder (alarm)'),
                  subtitle: Text(_due == null
                      ? 'Set a due date first'
                      : 'Notify me with an alarm so I don\'t forget'),
                  value: _reminder,
                  onChanged: _due == null ? null : (v) => setState(() => _reminder = v),
                ),
                if (_reminder)
                  DropdownButtonFormField<int>(
                    value: _offset,
                    decoration: const InputDecoration(
                        labelText: 'Remind me',
                        prefixIcon: Icon(Icons.notifications_active_outlined)),
                    items: [
                      for (final e in _offsets.entries)
                        DropdownMenuItem(value: e.key, child: Text(e.value)),
                    ],
                    onChanged: (v) => setState(() => _offset = v ?? 0),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.check),
                label: Text(widget.edit == null ? 'Add todo' : 'Save changes')),
          ],
        ),
      ),
    );
  }
}
