// Pickers for (1) transaction-category icons and (2) account icons
// (Indian banks, generic icons or a user uploaded image).
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../utils/icons.dart';
import '../utils/image_utils.dart';
import 'account_avatar.dart';
import 'common.dart';

/// Opens a searchable grid of category icons. Returns the chosen icon key.
Future<String?> pickCategoryIcon(BuildContext context, String current) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _CategoryIconSheet(current: current),
  );
}

class _CategoryIconSheet extends StatefulWidget {
  final String current;
  const _CategoryIconSheet({required this.current});
  @override
  State<_CategoryIconSheet> createState() => _CategoryIconSheetState();
}

class _CategoryIconSheetState extends State<_CategoryIconSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    // keys contain words like "restaurant", so a plain contains() search works
    final keys = kCategoryIcons.keys
        .where((k) => k.contains(_q.toLowerCase().trim().replaceAll(' ', '_')))
        .toList();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .75,
      maxChildSize: .95,
      builder: (context, scroll) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                  hintText: 'Search icons (food, car, home...)',
                  prefixIcon: Icon(Icons.search),
                  isDense: true),
              onChanged: (v) => setState(() => _q = v),
            ),
          ),
          Expanded(
            child: GridView.builder(
              controller: scroll,
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 64, mainAxisSpacing: 8, crossAxisSpacing: 8),
              itemCount: keys.length,
              itemBuilder: (_, i) {
                final k = keys[i];
                final sel = k == widget.current;
                final cs = Theme.of(context).colorScheme;
                return InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => Navigator.pop(context, k),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: sel ? cs.primaryContainer : cs.surfaceContainerHighest,
                      border: sel ? Border.all(color: cs.primary, width: 2) : null,
                    ),
                    child: Icon(kCategoryIcons[k], size: 28),
                  ),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}

/// Result of the account icon picker.
class AccountIconChoice {
  final String key;
  final Uint8List? blob; // set when the user uploaded an image
  const AccountIconChoice(this.key, this.blob);
}

/// Opens the account icon picker (banks / generic / upload).
Future<AccountIconChoice?> pickAccountIcon(
    BuildContext context, String currentKey, Uint8List? currentBlob) {
  return showModalBottomSheet<AccountIconChoice>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _AccountIconSheet(currentKey: currentKey, currentBlob: currentBlob),
  );
}

class _AccountIconSheet extends StatefulWidget {
  final String currentKey;
  final Uint8List? currentBlob;
  const _AccountIconSheet({required this.currentKey, required this.currentBlob});
  @override
  State<_AccountIconSheet> createState() => _AccountIconSheetState();
}

class _AccountIconSheetState extends State<_AccountIconSheet> {
  String _q = '';

  /// Lets the user pick an image from the phone, shrinks it and returns it.
  Future<void> _upload() async {
    try {
      final res = await LockGuard.run(() =>
          FilePicker.platform.pickFiles(type: FileType.image, withData: true));
      if (res == null || res.files.isEmpty) return;
      final bytes = res.files.single.bytes;
      if (bytes == null) return;
      final small = await resizeToIcon(bytes);
      if (mounted) {
        Navigator.pop(context, AccountIconChoice(widget.currentKey, small));
      }
    } catch (e) {
      if (mounted) showErrorDialog(context, 'Could not use that image: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.toLowerCase().trim();
    final banks = kIndianBanks
        .where((b) => q.isEmpty || b.name.toLowerCase().contains(q) || b.short.toLowerCase().contains(q))
        .toList();
    final generic = kGenericAccountIcons.keys
        .where((k) => q.isEmpty || k.contains(q))
        .toList();

    // one flat list of tiles: generic icons first, then banks
    final tiles = <Widget>[
      for (final k in generic)
        _tile(context, 'icon:$k', k[0].toUpperCase() + k.substring(1)),
      for (final b in banks) _tile(context, 'bank:${b.key}', b.name),
    ];

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .8,
      maxChildSize: .95,
      builder: (context, scroll) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(children: [
              TextField(
                decoration: const InputDecoration(
                    hintText: 'Search bank (HDFC, SBI, ...)',
                    prefixIcon: Icon(Icons.search),
                    isDense: true),
                onChanged: (v) => setState(() => _q = v),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _upload,
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Upload own image'),
                  ),
                ),
                if (widget.currentBlob != null) ...[
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => Navigator.pop(
                        context, AccountIconChoice(widget.currentKey, null)),
                    child: const Text('Remove image'),
                  ),
                ],
              ]),
            ]),
          ),
          Expanded(
            child: GridView(
              controller: scroll,
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 92,
                  mainAxisExtent: 92,
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6),
              children: tiles,
            ),
          ),
        ]),
      ),
    );
  }

  /// One selectable icon with its caption. Picking a built-in icon clears any
  /// uploaded image.
  Widget _tile(BuildContext context, String key, String label) {
    final sel = widget.currentBlob == null && widget.currentKey == key;
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.pop(context, AccountIconChoice(key, null)),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: sel ? cs.primaryContainer : null,
          border: sel ? Border.all(color: cs.primary, width: 2) : null,
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          AccountAvatar(iconKey: key, size: 44),
          const SizedBox(height: 4),
          Text(label,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10)),
        ]),
      ),
    );
  }
}
