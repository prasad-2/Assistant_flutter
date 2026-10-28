// Scheduled (automatic) backup settings: on/off, frequency, time of day,
// backup folder, how many backups to keep, "Back up now" and the last result.
import 'package:flutter/material.dart';

import '../../services/backup_schedule.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';

class BackupScheduleScreen extends StatefulWidget {
  const BackupScheduleScreen({super.key});
  @override
  State<BackupScheduleScreen> createState() => _BackupScheduleScreenState();
}

class _BackupScheduleScreenState extends State<BackupScheduleScreen> {
  BackupConfig? _c;
  bool _busy = false;

  /// Frequency options: label -> every N days.
  static const _freq = {
    'Daily': 1,
    'Every 2 days': 2,
    'Every 3 days': 3,
    'Weekly': 7,
    'Every 2 weeks': 14,
    'Monthly': 30,
  };
  static const _keepOptions = [3, 5, 10, 20, 50];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final c = await BackupSchedule.load();
    if (mounted) setState(() => _c = c);
  }

  /// Saves the given values (falling back to the current ones) and reloads.
  Future<void> _save({bool? enabled, int? days, TimeOfDay? time, int? keep}) async {
    final c = _c!;
    if ((enabled ?? c.enabled) && !c.hasFolder) {
      await showErrorDialog(context, 'Choose a backup folder first.');
      return;
    }
    await BackupSchedule.save(
      enabled: enabled ?? c.enabled,
      intervalDays: days ?? c.intervalDays,
      hour: time?.hour ?? c.hour,
      minute: time?.minute ?? c.minute,
      keep: keep ?? c.keep,
    );
    await _reload();
  }

  Future<void> _pickFolder() async {
    try {
      final name = await BackupSchedule.pickFolder();
      if (name != null) {
        await _reload();
        if (mounted) snack(context, 'Backup folder: $name');
      }
    } catch (e) {
      if (mounted) showErrorDialog(context, 'Could not select the folder: $e');
    }
  }

  Future<void> _runNow() async {
    if (!_c!.hasFolder) {
      showErrorDialog(context, 'Choose a backup folder first.');
      return;
    }
    setState(() => _busy = true);
    final r = await BackupSchedule.runNow();
    await _reload();
    if (mounted) {
      setState(() => _busy = false);
      snack(context, r);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Scheduled backup')),
      body: c == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 40),
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.schedule_send_outlined),
                  title: const Text('Automatic backup'),
                  subtitle: Text(c.enabled && c.nextTime != null
                      ? 'Next backup: ${fmtDateTime.format(c.nextTime!)}'
                      : 'Backs up the database by itself, even when the app is closed'),
                  value: c.enabled,
                  onChanged: (v) => _save(enabled: v),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.repeat),
                  title: const Text('Frequency'),
                  trailing: DropdownButton<int>(
                    value: _freq.containsValue(c.intervalDays) ? c.intervalDays : 1,
                    underline: const SizedBox.shrink(),
                    items: [
                      for (final e in _freq.entries)
                        DropdownMenuItem(value: e.value, child: Text(e.key)),
                    ],
                    onChanged: (v) => _save(days: v),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.access_time),
                  title: const Text('Time of day'),
                  trailing: Text(
                      TimeOfDay(hour: c.hour, minute: c.minute).format(context),
                      style: const TextStyle(fontSize: 16)),
                  onTap: () async {
                    final t = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay(hour: c.hour, minute: c.minute));
                    if (t != null) _save(time: t);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.folder_open),
                  title: const Text('Backup location'),
                  subtitle: Text(c.hasFolder
                      ? (c.folderName ?? 'Selected folder')
                      : 'Not selected – tap to choose a folder'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _pickFolder,
                ),
                ListTile(
                  leading: const Icon(Icons.layers_outlined),
                  title: const Text('Keep latest backups'),
                  subtitle: const Text('Older automatic backups are deleted'),
                  trailing: DropdownButton<int>(
                    value: _keepOptions.contains(c.keep) ? c.keep : 10,
                    underline: const SizedBox.shrink(),
                    items: [
                      for (final k in _keepOptions)
                        DropdownMenuItem(value: k, child: Text('$k')),
                    ],
                    onChanged: (v) => _save(keep: v),
                  ),
                ),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _runNow,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.backup),
                    label: const Text('Back up now'),
                  ),
                ),
                if (c.lastStatus != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    child: Text(
                      'Last backup: ${c.lastTime != null ? fmtDateTime.format(c.lastTime!) : '-'}\n${c.lastStatus}',
                      style: TextStyle(
                          color: c.lastStatus!.startsWith('Failed')
                              ? cs.error
                              : cs.onSurfaceVariant),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Backup files are plain copies of your database (named assistant_backup_<date>.db). Keep the folder private. To restore, use Settings → Restore from backup and pick one of these files.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
    );
  }
}
