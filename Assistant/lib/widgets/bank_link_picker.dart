// "Also create a bank transaction" switch + account + actual/scheduled choice.
// Used by debt entries and settle-up.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import 'common.dart';

class BankLinkPicker extends StatefulWidget {
  /// Called on every change: (enabled, accountId, status).
  final void Function(bool enabled, int? accountId, String status) onChanged;
  final String switchTitle;
  final String? helper;
  const BankLinkPicker(
      {super.key,
      required this.onChanged,
      this.switchTitle = 'Also create a bank transaction',
      this.helper});

  @override
  State<BankLinkPicker> createState() => _BankLinkPickerState();
}

class _BankLinkPickerState extends State<BankLinkPicker> {
  bool _on = false;
  int? _account;
  String _status = 'actual';

  void _notify() => widget.onChanged(_on, _account, _status);

  @override
  Widget build(BuildContext context) {
    final accounts = context.watch<AppState>().accounts;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        secondary: const Icon(Icons.account_balance_outlined),
        title: Text(widget.switchTitle),
        subtitle: widget.helper == null ? null : Text(widget.helper!),
        value: _on,
        onChanged: (v) {
          setState(() => _on = v);
          _notify();
        },
      ),
      if (_on) ...[
        const SizedBox(height: 6),
        DropdownButtonFormField<int>(
          value: _account,
          isExpanded: true,
          decoration: const InputDecoration(
              labelText: 'Bank account', prefixIcon: Icon(Icons.account_balance)),
          items: [
            for (final a in accounts)
              DropdownMenuItem(
                  value: a.id,
                  child: Text(accountPath(a, accounts),
                      overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) {
            setState(() => _account = v);
            _notify();
          },
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                  value: 'actual',
                  label: Text('Actual'),
                  icon: Icon(Icons.check_circle_outline)),
              ButtonSegment(
                  value: 'scheduled',
                  label: Text('Scheduled'),
                  icon: Icon(Icons.schedule)),
            ],
            selected: {_status},
            onSelectionChanged: (s) {
              setState(() => _status = s.first);
              _notify();
            },
          ),
        ),
      ],
    ]);
  }
}
