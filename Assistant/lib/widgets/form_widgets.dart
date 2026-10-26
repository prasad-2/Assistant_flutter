// Shared building blocks that give all forms the same modern look:
//   * FormBanner  – coloured gradient header at the top of a form
//   * FormSection – titled rounded card that groups related fields
import 'package:flutter/material.dart';

import 'common.dart';

/// Gradient header with an icon, title, subtitle and optional trailing widget.
class FormBanner extends StatelessWidget {
  final Color color;
  final IconData? icon;
  final Widget? leading; // replaces the icon (e.g. an avatar)
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Color foreground;

  const FormBanner({
    super.key,
    required this.color,
    this.icon,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.foreground = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [shade(color, .05), shade(color, -.12)]),
        boxShadow: [
          BoxShadow(
              color: color.withValues(alpha: .35),
              blurRadius: 14,
              offset: const Offset(0, 6))
        ],
      ),
      child: Row(children: [
        leading ??
            CircleAvatar(
              radius: 24,
              backgroundColor: foreground.withValues(alpha: .2),
              child: Icon(icon, color: foreground, size: 26),
            ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: foreground, fontSize: 18, fontWeight: FontWeight.w700)),
            if (subtitle != null)
              Text(subtitle!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: foreground.withValues(alpha: .85), fontSize: 13)),
          ]),
        ),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

/// A rounded card with a small icon + title, containing [children] with an
/// even vertical gap between them.
class FormSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  const FormSection(
      {super.key, required this.title, required this.icon, required this.children});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(top: 14),
      elevation: 0,
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: cs.outlineVariant.withValues(alpha: .5))),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, size: 18, color: cs.onPrimaryContainer),
            ),
            const SizedBox(width: 10),
            Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 14),
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: 14),
            children[i],
          ],
        ]),
      ),
    );
  }
}
