// Add / edit bank account form.
// A live preview banner at the top shows how the card will look.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../db/app_database.dart';
import '../../models/models.dart';
import '../../providers/app_state.dart';
import '../../utils/format.dart';
import '../../utils/icons.dart';
import '../../widgets/account_avatar.dart';
import '../../widgets/amount_field.dart';
import '../../widgets/color_picker.dart';
import '../../widgets/common.dart';
import '../../widgets/form_widgets.dart';
import '../../widgets/icon_pickers.dart';

class AccountFormPage extends StatefulWidget {
  final Account? edit; // null = add a new account
  const AccountFormPage({super.key, this.edit});
  @override
  State<AccountFormPage> createState() => _AccountFormPageState();
}

class _AccountFormPageState extends State<AccountFormPage> {
  final _key = GlobalKey<FormState>();

  // Controllers / state are initialised from the account being edited.
  late final _name = TextEditingController(text: widget.edit?.name ?? '');
  late final _owner = TextEditingController(text: widget.edit?.owner ?? '');
  late final _notes = TextEditingController(text: widget.edit?.notes ?? '');
  late final _limit = TextEditingController(
      text: (widget.edit?.isCredit ?? false)
          ? paiseToInput(widget.edit!.creditLimit)
          : '');
  late int _color = widget.edit?.color ?? kQuickColors.first;
  late int? _parent = widget.edit?.parentId;
  late bool _credit = widget.edit?.isCredit ?? false;
  late bool _regular = widget.edit?.isRegular ?? false;
  late String _iconKey = widget.edit?.iconKey ?? kDefaultAccountIcon;
  late Uint8List? _iconBlob = widget.edit?.iconBlob;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // keep the preview banner in sync while typing
    _name.addListener(() => setState(() {}));
    _owner.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _owner.dispose();
    _notes.dispose();
    _limit.dispose();
    super.dispose();
  }

  /// Opens the icon picker and stores the choice (bank / generic / upload).
  Future<void> _chooseIcon() async {
    final r = await pickAccountIcon(context, _iconKey, _iconBlob);
    if (r != null) {
      setState(() {
        _iconKey = r.key;
        _iconBlob = r.blob;
      });
    }
  }

  /// Validates the form, asks for confirmation when editing, then saves.
  /// Balance validation happens inside the database transaction.
  Future<void> _save() async {
    if (!_key.currentState!.validate()) return;
    final st = context.read<AppState>();
    final acc = Account(
      id: widget.edit?.id,
      name: _name.text,
      owner: _owner.text,
      color: _color,
      parentId: _parent,
      isCredit: _credit,
      creditLimit: _credit ? (parsePaise(_limit.text) ?? 0) : 0,
      isRegular: _regular,
      notes: _notes.text,
      iconKey: _iconKey,
      iconBlob: _iconBlob,
    );
    if (widget.edit != null) {
      final ok = await confirmDialog(context,
          title: 'Save changes?',
          message:
              'Update account "${widget.edit!.name}"? Balances will be recalculated.',
          confirmText: 'Save');
      if (!ok) return;
    }
    setState(() => _saving = true);
    try {
      await AppDatabase.instance.saveAccount(acc);
      await st.refreshFinance();
      if (mounted) Navigator.pop(context, true);
    } on ValidationException catch (e) {
      if (mounted) showErrorDialog(context, e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;

    // An account cannot be its own parent or the parent of its own ancestors,
    // so the account itself and all its descendants are not offered.
    final editId = widget.edit?.id;
    final blocked = editId == null
        ? <int>{}
        : {editId, ...descendantsOf(editId, st.accounts)};
    final parents = st.accounts.where((a) => !blocked.contains(a.id)).toList();
    if (_parent != null && !parents.any((a) => a.id == _parent)) _parent = null;

    // preview colours, computed like the real card header
    final base = Color(_color);
    final shown = Color.alphaBlend(base, cs.surfaceContainerHighest);
    final fg = onColor(shown);

    return Scaffold(
      appBar: AppBar(
          title: Text(widget.edit == null ? 'Add bank account' : 'Edit account')),
      body: Form(
        key: _key,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            // ── live preview of the card header ──
            FormBanner(
              color: shown,
              foreground: fg,
              leading: GestureDetector(
                onTap: _chooseIcon,
                child: Stack(children: [
                  AccountAvatar(iconKey: _iconKey, blob: _iconBlob, size: 54),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: CircleAvatar(
                      radius: 10,
                      backgroundColor: cs.primary,
                      child: Icon(Icons.edit, size: 12, color: cs.onPrimary),
                    ),
                  ),
                ]),
              ),
              title: _name.text.trim().isEmpty ? 'Account name' : _name.text.trim(),
              subtitle: _owner.text.trim().isEmpty
                  ? 'Owner name'
                  : _owner.text.trim() + (_credit ? '  •  Credit' : ''),
            ),
            FormSection(
              title: 'Account details',
              icon: Icons.badge_outlined,
              children: [
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                      labelText: 'Bank / account name',
                      prefixIcon: Icon(Icons.account_balance_outlined)),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                TextFormField(
                  controller: _owner,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                      labelText: 'Owner name',
                      prefixIcon: Icon(Icons.person_outline)),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                OutlinedButton.icon(
                  onPressed: _chooseIcon,
                  icon: const Icon(Icons.image_outlined),
                  label: const Text('Choose bank icon / upload image'),
                ),
              ],
            ),
            FormSection(
              title: 'Appearance',
              icon: Icons.palette_outlined,
              children: [
                ColorPickerField(
                    value: _color, onChanged: (c) => setState(() => _color = c)),
              ],
            ),
            FormSection(
              title: 'Type & linking',
              icon: Icons.account_tree_outlined,
              children: [
                // parent account (nested linking)
                DropdownButtonFormField<int?>(
                  value: _parent,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: 'Parent bank account',
                      prefixIcon: Icon(Icons.subdirectory_arrow_right),
                      helperText:
                          'Link as a virtual/child account of another account (any depth)'),
                  items: [
                    const DropdownMenuItem<int?>(
                        value: null, child: Text('None (top-level account)')),
                    for (final a in parents)
                      DropdownMenuItem<int?>(
                          value: a.id,
                          child: Text(accountPath(a, st.accounts),
                              overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setState(() => _parent = v),
                ),
                DropdownButtonFormField<bool>(
                  value: _credit,
                  decoration: const InputDecoration(
                      labelText: 'Account type',
                      prefixIcon: Icon(Icons.credit_card_outlined)),
                  items: const [
                    DropdownMenuItem(value: false, child: Text('Normal account')),
                    DropdownMenuItem(
                        value: true, child: Text('Credit account (credit card)')),
                  ],
                  onChanged: (v) => setState(() => _credit = v ?? false),
                ),
                if (_credit)
                  AmountField(
                      controller: _limit,
                      label: 'Credit limit',
                      icon: Icons.speed),
              ],
            ),
            FormSection(
              title: 'Notes & options',
              icon: Icons.sticky_note_2_outlined,
              children: [
                TextFormField(
                  controller: _notes,
                  minLines: 3,
                  maxLines: 8,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                      labelText: 'Notes (optional)',
                      alignLabelWithHint: true,
                      helperText: 'Branch, account details, reminders...'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Regular account'),
                  subtitle: const Text('Show this account summary on the Home screen'),
                  value: _regular,
                  onChanged: (v) => setState(() => _regular = v),
                ),
              ],
            ),
            if (widget.edit == null)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                    'Tip: after saving, add an "Opening Balance" transaction to set the starting balance.',
                    style: TextStyle(fontStyle: FontStyle.italic)),
              ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.check),
              label: Text(widget.edit == null ? 'Add account' : 'Save changes'),
            ),
          ],
        ),
      ),
    );
  }
}
