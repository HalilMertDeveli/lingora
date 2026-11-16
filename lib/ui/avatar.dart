import 'dart:typed_data';

import 'package:flutter/material.dart';

/// A round photo avatar, or [fallback] (the mascot or an animal emoji) when
/// there is no photo or it cannot be shown.
class PhotoAvatar extends StatelessWidget {
  const PhotoAvatar({super.key, required this.photo, required this.size, required this.fallback});

  final Uint8List? photo;
  final double size;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    final bytes = photo;
    if (bytes == null) {
      return SizedBox.square(
        dimension: size,
        child: Center(child: fallback),
      );
    }
    return ClipOval(
      child: Image.memory(
        bytes,
        key: const ValueKey('avatar-photo'),
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        // Decode at the shown size, not the stored 256 px.
        cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
        errorBuilder: (_, _, _) => SizedBox.square(
          dimension: size,
          child: Center(child: fallback),
        ),
      ),
    );
  }
}
