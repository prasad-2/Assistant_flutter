// Formatting helpers shared by the whole app (money + dates).
import 'package:intl/intl.dart';

/// Number formatter using the Indian digit grouping (1,00,000.00).
/// The app deliberately shows plain numbers without a currency symbol.
final NumberFormat _inr =
    NumberFormat.decimalPatternDigits(locale: 'en_IN', decimalDigits: 2);

/// Transaction / todo date-time format: dd-MMM-yy HH:mm
final DateFormat fmtDateTime = DateFormat('dd-MMM-yy HH:mm');

/// Date only: dd-MMM-yy
final DateFormat fmtDate = DateFormat('dd-MMM-yy');

/// Running clock on the home screen: dd-MMM-yyyy HH:mm:ss
final DateFormat fmtClock = DateFormat('dd-MMM-yyyy HH:mm:ss');

/// Formats an amount stored in paise, e.g. 12345 -> "123.45".
///
/// The app never prints a "+" / "-" prefix: credit/debit direction is shown
/// with colours (green/red) instead. Pass `hidden: true` to mask the value.
String formatInr(int paise, {bool hidden = false}) {
  if (hidden) return '*****.**';
  return _inr.format(paise / 100);
}

/// Parses user input such as "1,250.50" into paise (125050).
/// Returns null when the text is not a valid number.
int? parsePaise(String s) {
  final v = double.tryParse(s.trim().replaceAll(',', ''));
  if (v == null || v.isNaN || v.isInfinite) return null;
  return (v * 100).round();
}

/// Converts paise back to the plain text used inside input fields.
String paiseToInput(int p) => (p / 100).toStringAsFixed(2);
