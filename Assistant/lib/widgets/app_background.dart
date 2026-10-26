// Draws the user's background image behind the whole app.
//
// Layers (bottom -> top): solid surface colour, the image with the user's
// chosen visibility, then the app. Because scaffolds are transparent while an
// image is set (see buildTheme), the image shows through every screen.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';

class AppBackground extends StatelessWidget {
  final Widget child;
  const AppBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final surface = Theme.of(context).colorScheme.surface;
    return Stack(children: [
      // base colour (also what the image fades into at low visibility)
      Positioned.fill(child: ColoredBox(color: surface)),
      if (s.bgBytes != null)
        Positioned.fill(
          child: Opacity(
            opacity: s.bgOpacity,
            child: Image.memory(s.bgBytes!,
                fit: BoxFit.cover, gaplessPlayback: true),
          ),
        ),
      Positioned.fill(child: child),
    ]);
  }
}
