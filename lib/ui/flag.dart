import 'package:flutter/material.dart';

import '../theme.dart';

/// A small flag image (owner-supplied set, see docs/assets.md) with soft
/// corners and a hairline border so white stripes stay visible on cards.
class FlagIcon extends StatelessWidget {
  const FlagIcon(this.asset, {super.key, this.width = 28});
  final String asset;
  final double width;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: width * 2 / 3,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(width * 0.14),
      border: Border.all(color: context.palette.line),
    ),
    clipBehavior: Clip.antiAlias,
    child: Image.asset(
      asset,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, _, _) => ColoredBox(color: context.palette.surface),
    ),
  );
}
