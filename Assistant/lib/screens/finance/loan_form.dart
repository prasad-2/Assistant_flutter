// Create / edit a loan account.
// Fields: name, loan value, interest %, tenure (+unit), EMI start date, EMI
// frequency (every N day/month/year), foreclose %, penalty %, notes,
// plus colour and icon like a bank account. (No child accounts for loans.)
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../db/loan_repository.dart';
import '../../models/loan_models.dart';
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

class LoanFormPage extends StatefulWidget {
  final Loan? edit;
  const LoanFormPage({super.key, this.edit});
  @override
  State<LoanFormPage> createState() => _LoanFormPageState();
}

class _LoanFormPageState extends State<LoanFormPage> {
  final _key = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.edit?.name ?? '');
  late final _principal = TextEditingController(
      text: widget.edit == null ? '' : paiseToInput(widget.edit!.principal));
  late final _rate = TextEditingController(
      text: widget.edit == null ? '' : '${widget.edit!.rate}');
  late final _tenure = TextEditingController(
      text: widget.edit == null ? '' : '${widget.edit!.tenureValue}');
  late final _freq = TextEditingController(
      text: '${widget.edit?.freqValue ?? 1}');
  late final _foreclose = TextEditingController(
      text: widget.edit == null || widget.edit!.foreclosePct == 0
          ? ''
          : '${widget.edit!.foreclosePct}');
  late final _penalty = TextEditingController(
      text: widget.edit == null || widget.edit!.penaltyPct == 0
          ? ''
          : '${widget.edit!.penaltyPct}');
  late final _notes = TextEditingController(text: widget.edit?.notes ?? '');
  late String _tenureUnit = widget.edit?.tenureUnit ?? 'month';
  late String _freqUnit = widget.edit?.freqUnit ?? 'month';
  late DateTime _start = widget.edit?.startDate ?? DateTime.now();
  late int _color = widget.edit?.color ?? kQuickColors[1];
  late String _iconKey = widget.edit?.iconKey ?? kDefaultAccountIcon;
  late Uint8List? _iconBlob = widget.edit?.iconBlob;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _principal, _rate, _tenure, _freq, _foreclose, _penalty, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
        context: context,
        initialDate: _start,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100));
    if (d != null) setState(() => _start = d);
  }

  Future<void> _chooseIcon() async {
    final r = await pickAccountIcon(context, _iconKey, _iconBlob);
    if (r != null) setState(() {
      _iconKey = r.key;
      _iconBlob = r.blob;
    });
  }

  String? _positiveInt(String? v) {
    final n = int.tryParse((v ?? '').trim());
    return (n == null || n <= 0) ? 'Enter a whole number above 0' : null;
  }

  String? _percent(String? v, {bool optional = false}) {
    if (optional && (v == null || v.trim().isEmpty)) return null;
    final n = double.tryParse((v ?? '').trim());
    return (n == null || n < 0 || n > 100) ? 'Enter 0 – 100' : null;
  }

  /// Unit dropdown (days / months / years).
  Widget _unit(String value, ValueChanged<String> onChanged) =>
      DropdownButtonFormField<String>(
        value: value,
        decoration: const InputDecoration(labelText: 'Unit'),
        items: const [
          DropdownMenuItem(value: 'day', child: Text('Day(s)')),
          DropdownMenuItem(value: 'month', child: Text('Month(s)')),
          DropdownMenuItem(value: 'year', child: Text('Year(s)')),
        ],
        onChanged: (v) => onChanged(v ?? 'month'),
      );

  Future<void> _save() async {
    if (!_key.currentState!.validate()) return;
    final st = context.read<AppState>();
    final old = widget.edit;
    final loan = Loan(
      id: old?.id,
      name: _name.text,
      color: _color,
      iconKey: _iconKey,
      iconBlob: _iconBlob,
      principal: parsePaise(_principal.text) ?? 0,
      rate: double.parse(_rate.text.trim()),
      tenureValue: int.parse(_tenure.text.trim()),
      tenureUnit: _tenureUnit,
      startDate: DateTime(_start.year, _start.month, _start.day),
      freqValue: int.parse(_freq.text.trim()),
      freqUnit: _freqUnit,
      foreclosePct: double.tryParse(_foreclose.text.trim()) ?? 0,
      penaltyPct: double.tryParse(_penalty.text.trim()) ?? 0,
      emiAmount: old?.emiAmount ?? 0,
      notes: _notes.text,
      status: old?.status ?? 'active',
    );
    if (old != null) {
      final ok = await confirmDialog(context,
          title: 'Save changes?',
          message:
              'Existing EMI entries are NOT changed. After editing the terms, recalculate the EMI and generate the schedule again if needed.',
          confirmText: 'Save');
      if (!ok) return;
    }
    setState(() => _saving = true);
    try {
      await LoanRepository.instance.saveLoan(loan);
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
    final cs = Theme.of(context).colorScheme;
    final shown = Color.alphaBlend(Color(_color), cs.surfaceContainerHighest);
    return Scaffold(
      appBar: AppBar(title: Text(widget.edit == null ? 'Add loan' : 'Edit loan')),
      body: Form(
        key: _key,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            FormBanner(
              color: shown,
              foreground: onColor(shown),
              leading: GestureDetector(
                onTap: _chooseIcon,
                child: AccountAvatar(iconKey: _iconKey, blob: _iconBlob, size: 54),
              ),
              title: _name.text.trim().isEmpty ? 'Loan name' : _name.text.trim(),
              subtitle: 'Tap the icon to change it',
            ),
            FormSection(title: 'Loan', icon: Icons.request_quote_outlined, children: [
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                    labelText: 'Loan name', prefixIcon: Icon(Icons.label_outline)),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              AmountField(controller: _principal, label: 'Loan value'),
              TextFormField(
                controller: _rate,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Interest % per year',
                    prefixIcon: Icon(Icons.percent)),
                validator: (v) => _percent(v),
              ),
              ColorPickerField(value: _color, onChanged: (c) => setState(() => _color = c)),
            ]),
            FormSection(title: 'Tenure & EMI', icon: Icons.event_repeat, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: TextFormField(
                    controller: _tenure,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Tenure'),
                    validator: _positiveInt,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: _unit(_tenureUnit, (v) => setState(() => _tenureUnit = v))),
              ]),
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: _pickDate,
                child: InputDecorator(
                  decoration: const InputDecoration(
                      labelText: 'EMI payment start date',
                      prefixIcon: Icon(Icons.event),
                      suffixIcon: Icon(Icons.arrow_drop_down)),
                  child: Text(fmtDate.format(_start)),
                ),
              ),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: TextFormField(
                    controller: _freq,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'EMI every'),
                    validator: _positiveInt,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: _unit(_freqUnit, (v) => setState(() => _freqUnit = v))),
              ]),
            ]),
            FormSection(title: 'Charges (optional)', icon: Icons.gavel_outlined, children: [
              TextFormField(
                controller: _foreclose,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Foreclose charges %',
                    helperText: 'Charged on the outstanding principal',
                    prefixIcon: Icon(Icons.percent)),
                validator: (v) => _percent(v, optional: true),
              ),
              TextFormField(
                controller: _penalty,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Penalty charges %',
                    helperText: 'Charged on the EMI when paid late',
                    prefixIcon: Icon(Icons.percent)),
                validator: (v) => _percent(v, optional: true),
              ),
            ]),
            FormSection(title: 'Notes', icon: Icons.sticky_note_2_outlined, children: [
              TextFormField(
                controller: _notes,
                minLines: 3,
                maxLines: 8,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                    labelText: 'Notes (optional)', alignLabelWithHint: true),
              ),
            ]),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.check),
              label: Text(widget.edit == null ? 'Add loan' : 'Save changes'),
            ),
          ],
        ),
      ),
    );
  }
}
