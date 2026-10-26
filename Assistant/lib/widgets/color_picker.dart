// Free colour picker with transparency (hue / saturation / brightness /
// opacity sliders + hex input). The result is an ARGB int.
import 'package:flutter/material.dart';

import 'common.dart';

/// A few starting colours for convenience (any colour can still be picked).
const List<int> kQuickColors = [
  0xFF1565C0, 0xFF00796B, 0xFF2E7D32, 0xFF6A1B9A, 0xFFC62828, 0xFFEF6C00,
  0xFFAD1457, 0xFF283593, 0xFF4E342E, 0xFF455A64, 0xFFFFB300, 0xFF29B6F6,
];

/// Opens the picker sheet. Returns the ARGB int or null when cancelled.
/// With [allowOpacity] false the opacity slider is hidden and alpha is 100%.
Future<int?> showColorPickerSheet(BuildContext context, int initial,
    {bool allowOpacity = true}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ColorSheet(initial: initial, allowOpacity: allowOpacity),
  );
}

/// Form field that shows the chosen colour and opens the picker sheet.
class ColorPickerField extends StatelessWidget {
  final int value; // ARGB
  final ValueChanged<int> onChanged;
  const ColorPickerField(
      {super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = Color(value);
    final opacity = (c.a * 100).round();
    return InkWell(
      onTap: () async {
        final r = await showColorPickerSheet(context, value);
        if (r != null) onChanged(r);
      },
      child: InputDecorator(
        decoration: const InputDecoration(
            labelText: 'Card colour', suffixIcon: Icon(Icons.palette_outlined)),
        child: Row(children: [
          // checkerboard-ish backdrop so transparency is visible
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.grey.shade400,
                border: Border.all(color: Colors.black26)),
            child: Container(
                decoration: BoxDecoration(shape: BoxShape.circle, color: c)),
          ),
          const SizedBox(width: 12),
          Text('${_hex(value)}  •  opacity $opacity%'),
        ]),
      ),
    );
  }
}

String _hex(int argb) =>
    '#${argb.toRadixString(16).padLeft(8, '0').toUpperCase()}';

/// Parses "#RRGGBB" / "#AARRGGBB" (with or without #). Returns null if invalid.
int? _parseHex(String s) {
  var t = s.trim().replaceAll('#', '');
  if (t.length == 6) t = 'FF$t';
  if (t.length != 8) return null;
  return int.tryParse(t, radix: 16);
}

class _ColorSheet extends StatefulWidget {
  final int initial;
  final bool allowOpacity;
  const _ColorSheet({required this.initial, this.allowOpacity = true});
  @override
  State<_ColorSheet> createState() => _ColorSheetState();
}

class _ColorSheetState extends State<_ColorSheet> {
  late HSVColor _hsv = widget.allowOpacity
      ? HSVColor.fromColor(Color(widget.initial))
      : HSVColor.fromColor(Color(widget.initial)).withAlpha(1);
  late final TextEditingController _hexC =
      TextEditingController(text: _hex(widget.initial));

  /// Current colour as ARGB int.
  int get _argb => _hsv.toColor().toARGB32();

  /// Updates the colour from a slider and mirrors it into the hex field.
  void _set(HSVColor c) => setState(() {
        _hsv = c;
        _hexC.text = _hex(_argb);
      });

  @override
  void dispose() {
    _hexC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = _hsv.toColor();
    final surface = Theme.of(context).colorScheme.surface;
    final shown = Color.alphaBlend(color, surface); // how it will really look
    final pureHue = HSVColor.fromAHSV(1, _hsv.hue, 1, 1).toColor();
    final full = _hsv.withAlpha(1).toColor();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Pick a colour', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            // live preview
            Container(
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: Colors.grey.shade400,
              ),
              child: Container(
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14), color: color),
                alignment: Alignment.center,
                child: Text('Preview',
                    style: TextStyle(
                        color: onColor(shown),
                        fontWeight: FontWeight.bold,
                        fontSize: 18)),
              ),
            ),
            const SizedBox(height: 14),
            _GradientSlider(
              label: 'Hue',
              value: _hsv.hue / 360,
              colors: [
                for (var i = 0; i <= 6; i++)
                  HSVColor.fromAHSV(1, i * 60.0, 1, 1).toColor()
              ],
              onChanged: (v) => _set(_hsv.withHue(v * 360)),
            ),
            _GradientSlider(
              label: 'Saturation',
              value: _hsv.saturation,
              colors: [Colors.white, pureHue],
              onChanged: (v) => _set(_hsv.withSaturation(v)),
            ),
            _GradientSlider(
              label: 'Brightness',
              value: _hsv.value,
              colors: [Colors.black, HSVColor.fromAHSV(1, _hsv.hue, _hsv.saturation, 1).toColor()],
              onChanged: (v) => _set(_hsv.withValue(v)),
            ),
            if (widget.allowOpacity)
            _GradientSlider(
              label: 'Opacity  ${(_hsv.alpha * 100).round()}%',
              value: _hsv.alpha,
              colors: [full.withValues(alpha: 0), full],
              checker: true,
              onChanged: (v) => _set(_hsv.withAlpha(v)),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _hexC,
              decoration: const InputDecoration(
                  labelText: 'Hex (#RRGGBB or #AARRGGBB)', isDense: true),
              onChanged: (t) {
                final v = _parseHex(t);
                if (v != null) {
                  final c = HSVColor.fromColor(Color(v));
                  setState(() => _hsv = widget.allowOpacity ? c : c.withAlpha(1));
                }
              },
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 10, runSpacing: 10, children: [
              for (final q in kQuickColors)
                GestureDetector(
                  onTap: () => _set(HSVColor.fromColor(Color(q))),
                  child: CircleAvatar(radius: 15, backgroundColor: Color(q)),
                ),
            ]),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                  child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'))),
              const SizedBox(width: 10),
              Expanded(
                  child: FilledButton(
                      onPressed: () => Navigator.pop(context, _argb),
                      child: const Text('Use this colour'))),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// A draggable gradient bar returning a value from 0 to 1.
class _GradientSlider extends StatelessWidget {
  final String label;
  final double value;
  final List<Color> colors;
  final bool checker; // grey backdrop (for the opacity slider)
  final ValueChanged<double> onChanged;

  const _GradientSlider({
    required this.label,
    required this.value,
    required this.colors,
    required this.onChanged,
    this.checker = false,
  });

  static const double _thumb = 26;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        LayoutBuilder(builder: (context, c) {
          final w = c.maxWidth;
          // convert a touch x-position into a 0..1 value
          void update(double dx) =>
              onChanged(((dx - _thumb / 2) / (w - _thumb)).clamp(0.0, 1.0));
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => update(d.localPosition.dx),
            onPanDown: (d) => update(d.localPosition.dx),
            onPanUpdate: (d) => update(d.localPosition.dx),
            child: SizedBox(
              height: _thumb + 4,
              child: Stack(clipBehavior: Clip.none, children: [
                Positioned.fill(
                  top: 6,
                  bottom: 6,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: checker ? Colors.grey.shade400 : null),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          gradient: LinearGradient(colors: colors)),
                    ),
                  ),
                ),
                Positioned(
                  left: value.clamp(0.0, 1.0) * (w - _thumb),
                  top: 2,
                  child: Container(
                    width: _thumb,
                    height: _thumb,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        border: Border.all(color: Colors.black54, width: 2),
                        boxShadow: const [
                          BoxShadow(blurRadius: 3, color: Colors.black26)
                        ]),
                  ),
                ),
              ]),
            ),
          );
        }),
      ]),
    );
  }
}
