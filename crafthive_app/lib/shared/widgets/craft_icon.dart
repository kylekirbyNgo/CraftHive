import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/theme/app_colors.dart';

export 'craft_icon_paths.dart';

/// Draws one of the CraftHive stroke icons ([CraftIcons]).
class CraftIcon extends StatelessWidget {
  const CraftIcon(this.paths, {super.key, this.size = 20, this.color, this.strokeWidth = 1.9, this.semanticLabel});

  final String paths;
  final double size;
  final Color? color;
  final double strokeWidth;
  final String? semanticLabel;

  static String _hex(Color c) {
    final argb = c.toARGB32();
    return '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final c = color ?? IconTheme.of(context).color ?? AppColors.darkCocoa;
    final svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="${_hex(c)}" '
        'stroke-opacity="${c.a.toStringAsFixed(3)}" stroke-width="$strokeWidth" stroke-linecap="round" stroke-linejoin="round">$paths</svg>';
    final pic = SvgPicture.string(svg, width: size, height: size);
    if (semanticLabel == null) return ExcludeSemantics(child: pic);
    return Semantics(label: semanticLabel, image: true, child: pic);
  }
}
