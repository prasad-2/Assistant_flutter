// Add / edit transaction form (also used for "Mark as actual" and by the
// home-screen widget's quick-add dialog).
//
// Layout: coloured banner (live value) -> sections -> Save button.
// The calculator icon in the value field opens a calculator panel ON TOP of
// the form; "Use value" copies its result into the value field.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../db/app_database.dart';
import '../../models/models.dart';
import '../../providers/app_state.dart';
import '../../utils/format.dart';
import '../../utils/icons.dart';
import '../../widgets/calculator.dart';
import '../../widgets/common.dart';
import '../../widgets/form_widgets.dart';

class TransactionFormPage extends StatefulWidget {
  final int? editId; // null = add

  /// Opened from "Mark as actual" on a scheduled transaction: status is preset
  /// to actual and the date to now (both can still be changed).
  final bool completeMode;
  const TransactionFormPage({super.key, this.editId, this.completeMode = false});
  @override
  State<TransactionFormPage> createState() => _TransactionFormPageState();
}

class _TransactionFormPageState extends State<TransactionFormPage> {
  final _key = GlobalKey<FormState>();
  final _desc = TextEditingController();
  final _amt = TextEditingController();
  Category? _cat;
  int? _from; // account (or "from" account for self transfer)
  int? _to; // "to" account (self transfer only)
  DateTime _dt = DateTime.now();
  String _status = 'actual';
  bool _loading = true;
  bool _origActual = false; // an actual transaction cannot go back to scheduled
  bool _isTransferEdit = false; // two-leg <-> normal switch is not allowed
  bool _saving = false;
  bool _showCalc = false; // calculator panel visible

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _desc.dispose();
    _amt.dispose();
    super.dispose();
  }

  /// Loads the transaction being edited (if any) into the form fields.
  Future<void> _init() async {
    final st = context.read<AppState>();
    if (widget.editId != null) {
      final i = await AppDatabase.instance.loadInput(widget.editId!);
      _cat = st.categories.firstWhere((c) => c.id == i.categoryId);
      _isTransferEdit = _cat!.isTwoLeg;
      _desc.text = i.description;
      _amt.text = paiseToInput(i.amountPaise);
      _from = i.accountId;
      _to = i.toAccountId;
      _dt = i.dateTime;
      _status = i.status;
      _origActual = i.status == 'actual';
      if (widget.completeMode) {
        _status = 'actual';
        _dt = DateTime.now();
      }
    } else if (st.accounts.length == 1) {
      _from = st.accounts.first.id; // only one account: preselect it
    }
    if (mounted) setState(() => _loading = false);
  }

  /// Date picker followed by time picker.
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

  /// Validates input, confirms edits, then saves. The database performs the
  /// "insufficient balance" validation and rolls back on failure.
  Future<void> _save() async {
    if (!_key.currentState!.validate()) return;
    final st = context.read<AppState>();
    final input = TxnInput(
      categoryId: _cat!.id!,
      description: _desc.text,
      dateTime: _dt,
      amountPaise: parsePaise(_amt.text)!,
      accountId: _from!,
      toAccountId: _cat!.isTwoLeg ? _to : null,
      status: _status,
    );
    if (widget.editId != null) {
      final ok = await confirmDialog(context,
          title: 'Save changes?',
          message: _isTransferEdit
              ? 'Both legs of this self transfer will be updated and balances recalculated.'
              : 'This transaction will be updated and account balances recalculated.',
          confirmText: 'Save');
      if (!ok) return;
    }
    setState(() => _saving = true);
    try {
      if (widget.editId == null) {
        await AppDatabase.instance.addTransaction(input);
      } else {
        await AppDatabase.instance.updateTransaction(widget.editId!, input);
      }
      await st.refreshFinance();
      if (mounted) Navigator.pop(context, true);
    } on ValidationException catch (e) {
      if (mounted) showErrorDialog(context, e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Dropdown items showing the account colour dot and its nested path.
  List<DropdownMenuItem<int>> _accountItems(List<Account> all) => [
        for (final a in all)
          DropdownMenuItem<int>(
            value: a.id,
            child: Row(children: [
              CircleAvatar(radius: 6, backgroundColor: Color(a.color)),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(accountPath(a, all), overflow: TextOverflow.ellipsis)),
            ]),
          ),
      ];

  /// Banner colour tells the direction of money at a glance.
  Color _bannerColor(BuildContext context) {
    if (_cat == null) return Theme.of(context).colorScheme.primary;
    if (_cat!.isTransfer) return Colors.indigo;
    if (_cat!.isRepayment) return Colors.deepPurple;
    return _cat!.isCredit ? Colors.green.shade700 : Colors.red.shade600;
  }

  /// After the category changes, drop account selections that are not valid
  /// for it (credit bill repayment: from = non-credit, to = credit only).
  void _fixAccountsForCategory(List<Account> all) {
    if (_cat?.isRepayment ?? false) {
      final byId = {for (final a in all) a.id: a};
      if (byId[_from]?.isCredit ?? false) _from = null;
      if (!(byId[_to]?.isCredit ?? false)) _to = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final editing = widget.editId != null;

    // While editing, a two-entry transaction (self transfer / credit bill
    // repayment) stays two-entry and a normal one cannot become two-entry.
    final cats = st.categories.where((c) {
      if (!editing) return true;
      return _isTransferEdit ? c.isTwoLeg : !c.isTwoLeg;
    }).toList();
    final isTransfer = _cat?.isTwoLeg ?? false; // shows the "to" account
    final isRepay = _cat?.isRepayment ?? false;

    // Account choices. Repayment: FROM = non-credit, TO = credit only.
    final fromList =
        isRepay ? st.accounts.where((a) => !a.isCredit).toList() : st.accounts;
    final toList =
        isRepay ? st.accounts.where((a) => a.isCredit).toList() : st.accounts;
    final fromValue = fromList.any((a) => a.id == _from) ? _from : null;
    final toValue = toList.any((a) => a.id == _to) ? _to : null;

    return Scaffold(
      appBar: AppBar(
          title: Text(widget.completeMode
              ? 'Mark as actual'
              : editing
                  ? 'Edit transaction'
                  : 'Add transaction')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Stack(children: [
              // ───────── the form ─────────
              Form(
                key: _key,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                  children: [
                    // banner with live value
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _amt,
                      builder: (_, v, __) {
                        final p = parsePaise(v.text);
                        return FormBanner(
                          color: _bannerColor(context),
                          icon: categoryIconFor(_cat?.icon),
                          title: _cat?.name ?? 'Choose a category',
                          subtitle: _cat == null
                              ? 'Credit adds money, deduct removes it'
                              : _cat!.isTransfer
                                  ? 'Self transfer between your accounts'
                                  : _cat!.isRepayment
                                      ? 'Pays a credit account from a normal account'
                                      : _cat!.isCredit
                                      ? 'Credit  •  adds to the account'
                                      : 'Deduct  •  removes from the account',
                          trailing: Text(
                              p == null ? '0.00' : formatInr(p.abs()),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w600)),
                        );
                      },
                    ),
                    FormSection(
                      title: 'Category & account',
                      icon: Icons.category_outlined,
                      children: [
                        DropdownButtonFormField<int>(
                          value: _cat?.id,
                          isExpanded: true,
                          decoration: const InputDecoration(
                              labelText: 'Category',
                              prefixIcon: Icon(Icons.label_outline)),
                          items: [
                            for (final c in cats)
                              DropdownMenuItem(
                                value: c.id,
                                child: Row(children: [
                                  Icon(categoryIconFor(c.icon), size: 20),
                                  const SizedBox(width: 10),
                                  Expanded(
                                      child: Text('${c.name}  •  ${c.typeLabel}',
                                          overflow: TextOverflow.ellipsis)),
                                ]),
                              ),
                          ],
                          validator: (v) => v == null ? 'Select a category' : null,
                          onChanged: (v) => setState(() {
                            _cat = cats.firstWhere((c) => c.id == v);
                            _fixAccountsForCategory(st.accounts);
                          }),
                        ),
                        DropdownButtonFormField<int>(
                          value: fromValue,
                          isExpanded: true,
                          decoration: InputDecoration(
                              labelText: isTransfer ? 'From bank account' : 'Bank account',
                              helperText: isRepay
                                  ? 'Normal (non-credit) accounts only'
                                  : null,
                              prefixIcon: const Icon(Icons.account_balance_outlined)),
                          items: _accountItems(fromList),
                          validator: (v) => v == null ? 'Select an account' : null,
                          onChanged: (v) => setState(() => _from = v),
                        ),
                        if (isTransfer)
                          DropdownButtonFormField<int>(
                            value: toValue,
                            isExpanded: true,
                            decoration: InputDecoration(
                                labelText:
                                    isRepay ? 'To credit account' : 'To bank account',
                                helperText: isRepay
                                    ? (toList.isEmpty
                                        ? 'No credit account yet. Add one first.'
                                        : 'Credit accounts only')
                                    : null,
                                prefixIcon: const Icon(Icons.call_received)),
                            items: _accountItems(toList),
                            validator: (v) {
                              if (v == null) return 'Select the destination account';
                              if (v == _from) return 'Must differ from the "from" account';
                              return null;
                            },
                            onChanged: (v) => setState(() => _to = v),
                          ),
                      ],
                    ),
                    FormSection(
                      title: 'Value & date',
                      icon: Icons.payments_outlined,
                      children: [
                        TextFormField(
                          controller: _amt,
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w600),
                          decoration: InputDecoration(
                            labelText: 'Value',
                            prefixIcon: const Icon(Icons.payments_outlined),
                            // calculator: opens the panel on top of the form
                            suffixIcon: IconButton(
                              tooltip: 'Calculator',
                              icon: const Icon(Icons.calculate_outlined),
                              onPressed: () {
                                FocusScope.of(context).unfocus();
                                setState(() => _showCalc = true);
                              },
                            ),
                          ),
                          validator: (v) {
                            final p = parsePaise(v ?? '');
                            return (p == null || p <= 0)
                                ? 'Enter a value above 0'
                                : null;
                          },
                        ),
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
                      ],
                    ),
                    FormSection(
                      title: 'Details',
                      icon: Icons.notes,
                      children: [
                        TextFormField(
                          controller: _desc,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                              labelText: 'Description',
                              prefixIcon: Icon(Icons.short_text)),
                          validator: (v) =>
                              (v == null || v.trim().isEmpty) ? 'Required' : null,
                        ),
                        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          SizedBox(
                            width: double.infinity,
                            child: SegmentedButton<String>(
                              segments: [
                                const ButtonSegment(
                                    value: 'actual',
                                    label: Text('Actual'),
                                    icon: Icon(Icons.check_circle_outline)),
                                ButtonSegment(
                                    value: 'scheduled',
                                    label: const Text('Scheduled'),
                                    icon: const Icon(Icons.schedule),
                                    enabled: !_origActual),
                              ],
                              selected: {_status},
                              onSelectionChanged: (s) =>
                                  setState(() => _status = s.first),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              _status == 'scheduled'
                                  ? 'Scheduled: pending in future. Debits block funds in the available balance (which may go below zero); the actual balance is unchanged until it is marked actual.'
                                  : 'Actual: already completed; updates the actual balance.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ]),
                      ],
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: const Icon(Icons.check),
                      label: Text(editing ? 'Save changes' : 'Add transaction'),
                    ),
                  ],
                ),
              ),

              // ───────── calculator on top of the form ─────────
              if (_showCalc) ...[
                // dimmed scrim: tap outside the panel to close
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () => setState(() => _showCalc = false),
                    child: const ColoredBox(color: Colors.black45),
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: CalculatorPanel(
                    initial: (parsePaise(_amt.text) ?? 0) > 0
                        ? (parsePaise(_amt.text)! % 100 == 0
                            ? '${parsePaise(_amt.text)! ~/ 100}'
                            : paiseToInput(parsePaise(_amt.text)!))
                        : '',
                    onClose: () => setState(() => _showCalc = false),
                    onUse: (v) => setState(() {
                      _amt.text = v.toStringAsFixed(2); // auto-fill the value
                      _showCalc = false;
                    }),
                  ),
                ),
              ],
            ]),
    );
  }
}
