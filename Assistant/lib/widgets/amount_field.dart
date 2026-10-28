// A money text field with a calculator icon. Used by every form that asks for
// an amount, so the calculator is available "everywhere".
import 'package:flutter/material.dart';

import '../utils/format.dart';
import 'calculator.dart';

class AmountField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? helper;
  final IconData icon;
  final bool required; // must be a number above 0
  final String? Function(String?)? validator; // overrides [required]
  final ValueChanged<String>? onChanged;

  const AmountField({
    super.key,
    required this.controller,
    required this.label,
    this.helper,
    this.icon = Icons.payments_outlined,
    this.required = true,
    this.validator,
    this.onChanged,
  });

  /// Turns the field text into a calculator start value ("" when empty/zero).
  static String _initial(String text) {
    final p = parsePaise(text);
    if (p == null || p <= 0) return '';
    return p % 100 == 0 ? '${p ~/ 100}' : paiseToInput(p);
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        prefixIcon: Icon(icon),
        suffixIcon: IconButton(
          tooltip: 'Calculator',
          icon: const Icon(Icons.calculate_outlined),
          onPressed: () async {
            FocusScope.of(context).unfocus();
            final v = await showCalculatorDialog(context,
                initial: _initial(controller.text));
            if (v != null) {
              controller.text = v.toStringAsFixed(2);
              onChanged?.call(controller.text);
            }
          },
        ),
      ),
      validator: validator ??
          (v) {
            if (!required && (v == null || v.trim().isEmpty)) return null;
            final p = parsePaise(v ?? '');
            return (p == null || p <= 0) ? 'Enter a value above 0' : null;
          },
    );
  }
}
