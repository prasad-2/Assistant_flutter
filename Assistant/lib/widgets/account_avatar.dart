// Round icon of an account: uploaded image, Indian bank badge or generic icon.
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../utils/icons.dart';

class AccountAvatar extends StatelessWidget {
  /// `bank:<key>` or `icon:<key>` (see utils/icons.dart).
  final String iconKey;

  /// User uploaded image; wins over [iconKey] when present.
  final Uint8List? blob;
  final double size;

  const AccountAvatar(
      {super.key, required this.iconKey, this.blob, this.size = 40});

  @override
  Widget build(BuildContext context) {
    // 1. custom uploaded image
    if (blob != null) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            border: Border.all(color: Colors.white, width: 1.5)),
        clipBehavior: Clip.antiAlias,
        child: Image.memory(blob!, fit: BoxFit.cover, gaplessPlayback: true),
      );
    }
    // 2. Indian bank monogram badge
    if (iconKey.startsWith('bank:')) {
      final bank = bankByKey(iconKey.substring(5));
      if (bank != null) {
        return Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          padding: EdgeInsets.all(size * 0.12),
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Color(bank.color),
              border: Border.all(color: Colors.white, width: 1.5)),
          child: FittedBox(
            child: Text(bank.short,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .3)),
          ),
        );
      }
    }
    // 3. generic icon (also the fallback)
    final name = iconKey.startsWith('icon:') ? iconKey.substring(5) : 'bank';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: .92),
          border: Border.all(color: Colors.white, width: 1.5)),
      child: Icon(kGenericAccountIcons[name] ?? Icons.account_balance,
          size: size * 0.55, color: const Color(0xFF00695C)),
    );
  }
}
