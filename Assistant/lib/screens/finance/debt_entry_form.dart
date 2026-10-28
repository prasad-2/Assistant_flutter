// Add / edit a debt entry: description, date, value, "I lent" / "I borrowed",
// and optionally create the matching bank transaction (asks for the account).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../db/debt_repository.dart';
import '../../models/debt_models.dart';
import '../../models/models.dart';
import '../../providers/app_state.dart';
import '../../utils/format.dart';
import '../../widgets/amount_field.dart';
import '../../widgets/bank_link_picker.dart';
import '../../widgets/common.dart';
import '../../widgets/form_widgets.dart';
import 'debts_view.dart';

const _newPerson = -1;

class DebtEntryFormPage extends StatefulWidget {
  final int? personId; // preselected person
  final DebtEntry? edit;
  const DebtEntryFormPage({super.key, this.personId, this.edit});
  @override
  State<DebtEntryFormPage> createState() => _DebtEntryFormPageState();
}

class _DebtEntryFormPageState extends State<DebtEntryFormPage> {
  final _key = GlobalKey<FormState>();
  late final _desc = TextEditingController(text: widget.edit?.description ?? '');
  late final _amount = TextEditingController(
      text: widget.edit == null ? '' : paiseToInput(widget.edit!.amount));
  late int? _person = widget.edit?.personId ?? widget.personId;
  late String _direction = widget.edit?.direction ?? 'lent';
  late DateTime _dt = widget.edit?.dateTime ?? DateTime.now();
  bool _bankOn = false;
  int? _bankAccount;
  String _bankStatus = 'actual';
  bool _saving = false;

  @override
  void dispose() {
    _desc.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final d = await showDatePicker(
        context: context,
        initialDate: _dt,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100));
    if (d == null || !mounted) return;
    final t = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(_dt));
    if (t == null) return;
    setState(() => _dt = DateTime(d.year, d.month, d.day, t.hour, t.minute));
  }

  Future<void> _save() async {
    if (!_key.currentState!.validate()) return;
    if (_bankOn && _bankAccount == null) {
      showErrorDialog(context, 'Select the bank account for the bank transaction.');
      return;
    }
    final st = context.read<AppState>();
    final person = st.people.firstWhere((p) => p.id == _person);
    final old = widget.edit;
    setState(() => _saving = true);
    try {
      await DebtRepository.instance.saveEntry(
        DebtEntry(
          id: old?.id,
          personId: _person!,
          description: _desc.text,
          dateTime: _dt,
          amount: parsePaise(_amount.text) ?? 0,
          direction: _direction,
          isSetoff: old?.isSetoff ?? false,
          txnId: old?.txnId,
        ),
        link: _bankOn ? BankLink(_bankAccount!, _bankStatus) : null,
        personName: person.name,
      );
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
    final lent = _direction == 'lent';
    final color = lent ? Colors.green.shade700 : Colors.red.shade600;
    final editing = widget.edit != null;

    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'Edit entry' : 'Add debt entry')),
      body: Form(
        key: _key,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            FormBanner(
              color: color,
              icon: lent ? Icons.call_made : Icons.call_received,
              title: lent ? 'I lent' : 'I borrowed',
              subtitle: lent
                  ? 'They owe you this amount'
                  : 'You owe them this amount',
            ),
            FormSection(title: 'Who & what', icon: Icons.person_outline, children: [
              DropdownButtonFormField<int>(
                value: st.people.any((p) => p.id == _person) ? _person : null,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'Person', prefixIcon: Icon(Icons.person_outline)),
                items: [
                  for (final p in st.people)
                    DropdownMenuItem(value: p.id, child: Text(p.name)),
                  if (!editing)
                    const DropdownMenuItem(value: _newPerson, child: Text('➕  New person…')),
                ],
                validator: (v) => v == null ? 'Select a person' : null,
                onChanged: editing
                    ? null
                    : (v) async {
                        if (v == _newPerson) {
                          final id = await DebtActions.addPerson(context);
                          if (id != null) setState(() => _person = id);
                        } else {
                          setState(() => _person = v);
                        }
                      },
              ),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                        value: 'lent',
                        label: Text('I lent'),
                        icon: Icon(Icons.call_made)),
                    ButtonSegment(
                        value: 'borrowed',
                        label: Text('I borrowed'),
                        icon: Icon(Icons.call_received)),
                  ],
                  selected: {_direction},
                  onSelectionChanged: (v) => setState(() => _direction = v.first),
                ),
              ),
              TextFormField(
                controller: _desc,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                    labelText: 'Description', prefixIcon: Icon(Icons.short_text)),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
            ]),
            FormSection(title: 'Value & date', icon: Icons.payments_outlined, children: [
              AmountField(controller: _amount, label: 'Value'),
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: _pickDateTime,
                child: InputDecorator(
                  decoration: const InputDecoration(
                      labelText: 'Date & time',
                      prefixIcon: Icon(Icons.event),
                      suffixIcon: Icon(Icons.arrow_drop_down)),
                  child: Text(fmtDateTime.format(_dt)),
                ),
              ),
            ]),
            if (!editing)
              FormSection(title: 'Bank', icon: Icons.account_balance_outlined, children: [
                BankLinkPicker(
                  switchTitle: 'Also create a bank transaction',
                  helper: lent
                      ? 'Deducts the value from the chosen account'
                      : 'Credits the value to the chosen account',
                  onChanged: (on, acc, status) {
                    _bankOn = on;
                    _bankAccount = acc;
                    _bankStatus = status;
                  },
                ),
                Text(
                    'You can also link an existing bank transaction later from the entry menu.',
                    style: Theme.of(context).textTheme.bodySmall),
              ]),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.check),
              label: Text(editing ? 'Save changes' : 'Add entry'),
              style: FilledButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
