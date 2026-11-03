// History of "Distribute balance" operations (newest first). Each entry shows
// the source account, the total, the date and - expandable - every target with
// its percentage and amount.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../db/app_database.dart';
import '../../models/distribution_models.dart';
import '../../providers/app_state.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';

class DistributionHistoryScreen extends StatefulWidget {
  const DistributionHistoryScreen({super.key});
  @override
  State<DistributionHistoryScreen> createState() => _DistributionHistoryScreenState();
}

class _DistributionHistoryScreenState extends State<DistributionHistoryScreen> {
  List<Distribution> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await AppDatabase.instance.distributions();
    if (!mounted) return;
    setState(() {
      _items = list;
      _loading = false;
    });
  }

  /// Removes the history record only (the self transfers stay).
  Future<void> _delete(Distribution d) async {
    final ok = await confirmDialog(context,
        title: 'Delete history entry?',
        message:
            'Remove this record from the history? The ${d.lines.length} self transfer(s) it created are NOT deleted.',
        confirmText: 'Delete');
    if (!ok) return;
    await AppDatabase.instance.deleteDistribution(d.id!);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // reload when finance data changes elsewhere (e.g. a new distribution)
    context.select<AppState, int>((s) => s.financeVersion);
    return Scaffold(
      appBar: AppBar(title: const Text('Distribution history')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No distributions yet.\nUse "Distribute balance" in the Finance section.',
                        textAlign: TextAlign.center),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
                  itemCount: _items.length,
                  itemBuilder: (_, i) {
                    final d = _items[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ExpansionTile(
                        shape: const Border(),
                        collapsedShape: const Border(),
                        leading: CircleAvatar(
                          backgroundColor: cs.primaryContainer,
                          child: Icon(Icons.call_split, color: cs.onPrimaryContainer),
                        ),
                        title: Text(d.fromName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                            '${fmtDateTime.format(d.dateTime)}  •  ${d.lines.length} account${d.lines.length == 1 ? '' : 's'}'
                            '${d.isScheduled ? '  •  Scheduled' : ''}',
                            style: const TextStyle(fontSize: 12)),
                        trailing: Text(formatInr(d.total),
                            style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w500,
                                color: debitColor(context))),
                        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
                        children: [
                          for (final l in d.lines)
                            ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                  l.txnId == null ? Icons.link_off : Icons.link,
                                  size: 18,
                                  color: cs.onSurfaceVariant),
                              title: Text(l.toName),
                              subtitle: Text(
                                  '${l.pct.toStringAsFixed(2)} %${l.txnId == null ? '  •  transaction removed' : ''}',
                                  style: const TextStyle(fontSize: 11)),
                              trailing: Text(formatInr(l.amount),
                                  style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                      color: creditColor(context))),
                            ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: () => _delete(d),
                              icon: const Icon(Icons.delete_outline, size: 18),
                              label: const Text('Delete record'),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
