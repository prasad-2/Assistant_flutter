// EMI maths and schedule generation (pure functions, no UI / DB).
import 'dart:math' as math;

/// Converts "N day/month/year" to months (a day counts as 1/30.4375 month).
double unitToMonths(int value, String unit) {
  switch (unit) {
    case 'year':
      return value * 12.0;
    case 'day':
      return value / 30.4375;
    default:
      return value.toDouble();
  }
}

/// Adds [value] days / months / years to [d]. Month arithmetic keeps the day
/// of month where possible (31-Jan + 1 month = 28/29-Feb).
DateTime addPeriod(DateTime d, int value, String unit) {
  if (unit == 'day') {
    return DateTime(d.year, d.month, d.day + value, d.hour, d.minute);
  }
  final months = unit == 'year' ? value * 12 : value;
  final total = d.month - 1 + months;
  final y = d.year + total ~/ 12;
  final m = total % 12 + 1;
  final lastDay = DateTime(y, m + 1, 0).day;
  return DateTime(y, m, math.min(d.day, lastDay), d.hour, d.minute);
}

/// How many EMIs fit into the tenure (at least 1).
int installmentCount(
    int tenureValue, String tenureUnit, int freqValue, String freqUnit) {
  final n = (unitToMonths(tenureValue, tenureUnit) /
          unitToMonths(freqValue, freqUnit))
      .round();
  return n < 1 ? 1 : n;
}

/// Interest rate per EMI period (annual % -> fraction per period).
double periodRate(double annualPct, int freqValue, String freqUnit) =>
    annualPct / 100 * unitToMonths(freqValue, freqUnit) / 12;

/// Standard reducing-balance EMI in paise:  P·r·(1+r)^n / ((1+r)^n − 1).
int calcEmi(int principal, double annualPct, int n, int freqValue, String freqUnit) {
  final r = periodRate(annualPct, freqValue, freqUnit);
  if (r == 0) return (principal / n).round();
  final f = math.pow(1 + r, n);
  return (principal * r * f / (f - 1)).round();
}

/// One generated instalment.
class EmiRow {
  final int no;
  final DateTime due;
  final int emi;
  final int principalPart;
  final int interestPart;
  const EmiRow(this.no, this.due, this.emi, this.principalPart, this.interestPart);
}

/// Builds the full schedule. Every EMI is [emi] except the last one, which
/// clears whatever balance is left (so rounding never leaves a remainder).
List<EmiRow> buildSchedule({
  required int principal,
  required double annualPct,
  required int n,
  required int emi,
  required DateTime start,
  required int freqValue,
  required String freqUnit,
}) {
  final r = periodRate(annualPct, freqValue, freqUnit);
  var balance = principal;
  final rows = <EmiRow>[];
  for (var k = 0; k < n; k++) {
    final interest = (balance * r).round();
    int principalPart;
    int amount;
    if (k == n - 1) {
      principalPart = balance; // last EMI clears the balance
      amount = principalPart + interest;
    } else {
      principalPart = (emi - interest).clamp(0, balance);
      amount = emi;
    }
    balance -= principalPart;
    rows.add(EmiRow(k + 1, addPeriod(start, freqValue * k, freqUnit), amount,
        principalPart, interest));
  }
  return rows;
}
