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

/// Reverse EMI calculation: finds the ANNUAL interest % for which [n] EMIs of
/// [emi] repay [principal]. Solves  emi = P·r / (1 − (1+r)^−n)  for r by
/// bisection (the right side grows with r), then scales r to a yearly rate.
/// Returns null when the EMI is too small to repay the loan.
double? solveAnnualRate({
  required int principal,
  required int emi,
  required int n,
  required int freqValue,
  required String freqUnit,
}) {
  if (principal <= 0 || n <= 0 || emi <= 0) return null;
  // all EMIs together must at least cover the principal (1 paise rounding / EMI)
  if (emi * n < principal - n) return null;
  final p = principal.toDouble();
  double f(double r) => r == 0 ? p / n : p * r / (1 - math.pow(1 + r, -n));
  final target = emi.toDouble();
  if (target <= f(0)) return 0.0; // exactly principal / n  ->  0 % interest
  var lo = 0.0;
  var hi = 1.0;
  var guard = 0;
  while (f(hi) < target && guard++ < 200) {
    hi *= 2;
  }
  for (var i = 0; i < 200; i++) {
    final mid = (lo + hi) / 2;
    if (f(mid) < target) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  final r = (lo + hi) / 2;
  return r * 12 / unitToMonths(freqValue, freqUnit) * 100;
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
