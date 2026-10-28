// "Loans" tab of the Finance section: list of loan cards.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/app_state.dart';
import '../../widgets/loan_card.dart';
import 'loan_detail.dart';

class LoansView extends StatelessWidget {
  const LoansView({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    if (s.loans.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
              'No loans yet.\nTap "Add loan" to create one, then calculate its EMI and generate the EMI schedule.',
              textAlign: TextAlign.center),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
      children: [
        for (final l in s.loans)
          LoanCard(
            summary: l,
            hidden: s.hideBalances,
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => LoanDetailPage(loanId: l.loan.id!))),
          ),
      ],
    );
  }
}
