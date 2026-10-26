// Settings tab: theme, balance privacy, category master data, app lock,
// backup & restore and a hint about the home-screen widget.
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../main.dart' show kAppName;
import '../../models/models.dart';
import '../../providers/app_state.dart';
import '../../services/auth_service.dart';
import '../../services/backup_service.dart';
import '../../utils/image_utils.dart';
import '../../widgets/color_picker.dart';
import '../../widgets/common.dart';
import '../lock_screen.dart';
import 'categories_screen.dart';
import 'security_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  /// Backup requires authentication when the app lock is enabled.
  Future<void> _backup(BuildContext context) async {
    final st = context.read<AppState>();
    if (!await requireAuth(context, st.auth)) return;
    try {
      final p = await BackupService.backup();
      if (context.mounted) {
        snack(context, p == null ? 'Backup cancelled' : 'Backup saved');
      }
    } catch (e) {
      if (context.mounted) showErrorDialog(context, 'Backup failed: $e');
    }
  }

  /// Restore: warn -> authenticate -> pick file -> replace -> reload state.
  Future<void> _restore(BuildContext context) async {
    final st = context.read<AppState>();
    final ok = await confirmDialog(context,
        title: 'Restore backup?',
        message:
            'ALL current data (accounts, transactions, categories, todos) will be replaced by the backup file. This cannot be undone.',
        confirmText: 'Continue');
    if (!ok || !context.mounted) return;
    if (!await requireAuth(context, st.auth)) return;
    try {
      final done = await BackupService.restore();
      if (done) {
        await st.load(); // reload lists and re-create todo alarms
        if (context.mounted) snack(context, 'Backup restored');
      }
    } on ValidationException catch (e) {
      if (context.mounted) showErrorDialog(context, e.message);
    } catch (e) {
      if (context.mounted) showErrorDialog(context, 'Restore failed: $e');
    }
  }

  /// Picks an image, shrinks it (saves space in the DB) and sets it as the
  /// app-wide background.
  Future<void> _pickBackground(BuildContext context) async {
    final st = context.read<AppState>();
    try {
      final res = await LockGuard.run(() =>
          FilePicker.platform.pickFiles(type: FileType.image, withData: true));
      if (res == null || res.files.isEmpty || res.files.single.bytes == null) {
        return;
      }
      final small = await resizeToIcon(res.files.single.bytes!, size: 900);
      await st.setBackground(small);
    } catch (e) {
      if (context.mounted) showErrorDialog(context, 'Could not use that image: $e');
    }
  }

  /// Opaque theme-colour picker; returns an ARGB int or null.
  Future<int?> _pickSeed(BuildContext context, int current) =>
      showColorPickerSheet(context, current, allowOpacity: false);

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(children: [
        const _Header('Appearance'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(
                  value: ThemeMode.system,
                  label: Text('System'),
                  icon: Icon(Icons.brightness_auto)),
              ButtonSegment(
                  value: ThemeMode.light,
                  label: Text('Light'),
                  icon: Icon(Icons.light_mode)),
              ButtonSegment(
                  value: ThemeMode.dark,
                  label: Text('Dark'),
                  icon: Icon(Icons.dark_mode)),
            ],
            selected: {s.themeMode},
            onSelectionChanged: (v) => s.setTheme(v.first),
          ),
        ),
        // ── theme colour (any colour; optional separate dark-mode colour) ──
        ListTile(
          leading: CircleAvatar(
              radius: 14, backgroundColor: Color(s.seedLight)),
          title: Text(s.seedDark == null ? 'Theme colour' : 'Light mode colour'),
          subtitle: const Text('Buttons, highlights and tinted surfaces'),
          trailing: const Icon(Icons.palette_outlined),
          onTap: () async {
            final c = await _pickSeed(context, s.seedLight);
            if (c != null) s.setSeedColors(c, s.seedDark);
          },
        ),
        SwitchListTile(
          secondary: const Icon(Icons.dark_mode_outlined),
          title: const Text('Different colour for dark mode'),
          value: s.seedDark != null,
          onChanged: (v) => s.setSeedColors(s.seedLight, v ? s.seedLight : null),
        ),
        if (s.seedDark != null)
          ListTile(
            leading: CircleAvatar(
                radius: 14, backgroundColor: Color(s.seedDark!)),
            title: const Text('Dark mode colour'),
            trailing: const Icon(Icons.palette_outlined),
            onTap: () async {
              final c = await _pickSeed(context, s.seedDark!);
              if (c != null) s.setSeedColors(s.seedLight, c);
            },
          ),
        if (s.seedLight != AppState.kDefaultSeed || s.seedDark != null)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 12),
              child: TextButton.icon(
                onPressed: () => s.setSeedColors(AppState.kDefaultSeed, null),
                icon: const Icon(Icons.restart_alt),
                label: const Text('Reset colour to default'),
              ),
            ),
          ),
        // ── background image with adjustable visibility ──
        ListTile(
          leading: s.bgBytes == null
              ? const Icon(Icons.wallpaper)
              : ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(s.bgBytes!,
                      width: 40, height: 40, fit: BoxFit.cover)),
          title: const Text('Background image'),
          subtitle: Text(s.bgBytes == null
              ? 'Use your own picture behind the whole app'
              : 'Image set'),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
                tooltip: 'Choose image',
                icon: const Icon(Icons.upload_file),
                onPressed: () => _pickBackground(context)),
            if (s.bgBytes != null)
              IconButton(
                  tooltip: 'Remove image',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => s.setBackground(null)),
          ]),
        ),
        if (s.bgBytes != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Row(children: [
              const Icon(Icons.opacity, size: 20),
              Expanded(
                child: Slider(
                  min: 0.1,
                  max: 1.0,
                  divisions: 18,
                  value: s.bgOpacity,
                  label: '${(s.bgOpacity * 100).round()}%',
                  onChanged: s.setBgOpacity,
                ),
              ),
              Text('${(s.bgOpacity * 100).round()}%'),
            ]),
          ),
        SwitchListTile(
          secondary: const Icon(Icons.visibility_off_outlined),
          title: const Text('Hide balances'),
          value: s.hideBalances,
          onChanged: (_) => s.toggleHide(),
        ),
        const _Header('Finance'),
        ListTile(
          leading: const Icon(Icons.category_outlined),
          title: const Text('Transaction categories'),
          subtitle: const Text('Master data: add, edit, delete, icons'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const CategoriesScreen())),
        ),
        const _Header('Security'),
        ListTile(
          leading: const Icon(Icons.lock_outline),
          title: const Text('App lock'),
          subtitle: Text(!s.auth.enabled
              ? 'Off'
              : s.auth.method == 'device'
                  ? 'On – biometrics / device lock'
                  : s.auth.method == 'pin_only'
                      ? 'On – app PIN / password only'
                      : 'On – app PIN / password + biometrics'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const SecurityScreen())),
        ),
        const _Header('Backup & restore'),
        ListTile(
          leading: const Icon(Icons.backup_outlined),
          title: const Text('Take backup'),
          subtitle: const Text('Save the complete app database to a file'),
          onTap: () => _backup(context),
        ),
        ListTile(
          leading: const Icon(Icons.restore),
          title: const Text('Restore from backup'),
          subtitle: const Text('Replace all data using a backup file'),
          onTap: () => _restore(context),
        ),
        const _Header('Home screen widget'),
        const ListTile(
          leading: Icon(Icons.widgets_outlined),
          title: Text('Quick add widget'),
          subtitle: Text(
              'Long-press your home screen → Widgets → $kAppName. Add transactions and todos without opening the app.'),
        ),
      ]),
    );
  }
}

/// Small coloured section title.
class _Header extends StatelessWidget {
  final String t;
  const _Header(this.t);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
        child: Text(t,
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );
}
