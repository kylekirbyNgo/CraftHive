import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models.dart';
import 'craft_icon.dart';

// ---------------------------------------------------------------------------
// Colour for status tones (section 7.1: fern success, amber warning, brick error, teal info)
// ---------------------------------------------------------------------------
({Color ink, Color tint}) toneColors(Tone tone) => switch (tone) {
      Tone.success => (ink: AppColors.fern, tint: AppColors.fernTint),
      Tone.warning => (ink: AppColors.amberText, tint: AppColors.amberTint),
      Tone.error => (ink: AppColors.brick, tint: AppColors.brickTint),
      Tone.info => (ink: AppColors.slateTeal, tint: AppColors.tealTint),
      Tone.seller => (ink: AppColors.clayText, tint: AppColors.clayTint),
      Tone.neutral => (ink: AppColors.grayBrown, tint: AppColors.white),
    };

/// Keeps content at a readable width on tablets and landscape phones.
class ResponsiveCenter extends StatelessWidget {
  const ResponsiveCenter({super.key, required this.child, this.maxWidth = Insets.maxContentWidth});
  final Widget child;
  final double maxWidth;
  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        heightFactor: 1,
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child),
      );
}

/// Round icon button (40 px visual, 44 px touch target) used in top bars.
class RoundIconButton extends StatelessWidget {
  const RoundIconButton({super.key, required this.icon, required this.tooltip, this.onPressed, this.background = AppColors.lightSand, this.color = AppColors.darkCocoa, this.size = 40, this.badge});
  final String icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color background;
  final Color color;
  final double size;
  final int? badge;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: background,
      shape: const CircleBorder(side: BorderSide(color: AppColors.linen)),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(width: size, height: size, child: Center(child: CraftIcon(icon, size: size * 0.5, color: color))),
      ),
    );
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: Padding(
          padding: EdgeInsets.all(((Insets.minTouch - size) / 2).clamp(0.0, 8.0)),
          child: badge == null || badge == 0
              ? button
              : Badge(label: Text('$badge'), backgroundColor: AppColors.brick, offset: const Offset(2, -2), child: button),
        ),
      ),
    );
  }
}

/// Back button that pops, or returns home when there is nothing to pop.
class BackRoundButton extends StatelessWidget {
  const BackRoundButton({super.key, this.background = AppColors.lightSand, this.fallback = '/home'});
  final Color background;
  final String fallback;
  @override
  Widget build(BuildContext context) => RoundIconButton(
        icon: CraftIcons.back,
        tooltip: 'Go back',
        background: background,
        onPressed: () => context.canPop() ? context.pop() : context.go(fallback),
      );
}

/// Top bar used by every detail screen: back button, title and optional action.
class ScreenHeader extends StatelessWidget implements PreferredSizeWidget {
  const ScreenHeader({super.key, required this.title, this.subtitle, this.trailing, this.showBack = true, this.fallback = '/home'});
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final bool showBack;
  final String fallback;

  @override
  Size get preferredSize => Size.fromHeight(subtitle == null ? 70 : 88);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Insets.screen - 2, 10, Insets.screen - 2, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (showBack) BackRoundButton(fallback: fallback) else const SizedBox(width: 2),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(header: true, child: Text(title, style: AppText.screenTitle, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  if (subtitle != null) Text(subtitle!, style: AppText.caption.copyWith(fontSize: 13)),
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

enum ButtonKind { primary, outline, clayOutline, honey, soft, danger }

/// The 52 px buttons from the design system.
class AppButton extends StatelessWidget {
  const AppButton({super.key, required this.label, this.onPressed, this.kind = ButtonKind.primary, this.icon, this.height = Insets.buttonHeight, this.loading = false, this.expand = true});
  final String label;
  final VoidCallback? onPressed;
  final ButtonKind kind;
  final String? icon;
  final double height;
  final bool loading;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, border) = switch (kind) {
      ButtonKind.primary => (AppColors.moss, AppColors.white, AppColors.moss),
      ButtonKind.outline => (Colors.transparent, AppColors.moss, AppColors.moss),
      ButtonKind.clayOutline => (AppColors.white, AppColors.clayText, AppColors.clay),
      ButtonKind.honey => (AppColors.softHoney, AppColors.darkCocoa, AppColors.softHoney),
      ButtonKind.soft => (AppColors.lightSand, AppColors.darkCocoa, AppColors.linen),
      ButtonKind.danger => (AppColors.white, AppColors.brick, AppColors.brick),
    };
    final disabled = onPressed == null || loading;
    final child = loading
        ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: fg))
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[CraftIcon(icon!, size: 19, color: fg), const SizedBox(width: 8)],
              Flexible(child: Text(label, style: AppText.button.copyWith(color: fg, fontSize: height < 46 ? 14 : 16), overflow: TextOverflow.ellipsis)),
            ],
          );
    final btn = Opacity(
      opacity: disabled && !loading ? 0.5 : 1,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(borderRadius: Radii.button, side: BorderSide(color: border, width: 1.5)),
        child: InkWell(
          borderRadius: Radii.button,
          onTap: disabled ? null : onPressed,
          child: SizedBox(height: height, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Center(child: child))),
        ),
      ),
    );
    return Semantics(button: true, enabled: !disabled, label: label, excludeSemantics: true, child: expand ? SizedBox(width: double.infinity, child: btn) : btn);
  }
}

/// Label-above text field (Milestone 1 "Form fields" component).
class LabeledField extends StatelessWidget {
  const LabeledField({
    super.key,
    required this.label,
    this.controller,
    this.hint,
    this.icon,
    this.helper,
    this.obscure = false,
    this.suffix,
    this.keyboardType,
    this.validator,
    this.maxLines = 1,
    this.maxLength,
    this.prefixText,
    this.onChanged,
    this.textInputAction,
    this.readOnly = false,
    this.onTap,
    this.autofillHints,
    this.onSubmitted,
    this.errorText,
    this.inputFormatters,
    this.enabled = true,
  });

  final String label;
  final TextEditingController? controller;
  final String? hint;
  final String? icon;
  final String? helper;
  final bool obscure;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final int maxLines;
  final int? maxLength;
  final String? prefixText;
  final ValueChanged<String>? onChanged;
  final TextInputAction? textInputAction;
  final bool readOnly;
  final VoidCallback? onTap;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onSubmitted;

  /// An error from the server (e.g. "username taken"), shown under the field.
  final String? errorText;
  final List<TextInputFormatter>? inputFormatters;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppText.label),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboardType,
          validator: validator,
          maxLines: maxLines,
          maxLength: maxLength,
          onChanged: onChanged,
          readOnly: readOnly,
          onTap: onTap,
          autofillHints: autofillHints,
          onFieldSubmitted: onSubmitted,
          inputFormatters: inputFormatters,
          enabled: enabled,
          textInputAction: textInputAction ?? (maxLines > 1 ? TextInputAction.newline : TextInputAction.next),
          style: AppText.body.copyWith(fontSize: 15),
          decoration: InputDecoration(
            hintText: hint,
            helperText: helper,
            helperMaxLines: 2,
            errorText: errorText,
            errorMaxLines: 3,
            prefixText: prefixText,
            prefixStyle: AppText.body.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
            prefixIcon: icon == null ? null : Padding(padding: const EdgeInsets.only(left: 14, right: 10), child: CraftIcon(icon!, size: 18, color: AppColors.grayBrown)),
            prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
            suffixIcon: suffix,
          ),
        ),
      ],
    );
  }
}

/// Pill-shaped selectable chip.
class AppChip extends StatelessWidget {
  const AppChip({super.key, required this.label, this.selected = false, this.onTap, this.color = AppColors.moss, this.icon, this.height = 36});
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final Color color;
  final String? icon;
  final double height;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AppColors.white : AppColors.darkCocoa;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: selected ? color : AppColors.white,
        shape: StadiumBorder(side: BorderSide(color: selected ? color : AppColors.linen, width: 1.5)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Container(
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[CraftIcon(icon!, size: 15, color: fg, strokeWidth: 2.4), const SizedBox(width: 6)],
              Text(label, style: AppText.label.copyWith(color: fg)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Coloured status tag (Pending, Accepted, Sold out…).
class StatusPill extends StatelessWidget {
  const StatusPill(this.label, {super.key, this.tone = Tone.neutral, this.filled = false});
  final String label;
  final Tone tone;
  final bool filled;
  @override
  Widget build(BuildContext context) {
    final c = toneColors(tone);
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(color: filled ? c.tint : AppColors.white, borderRadius: Radii.pill, border: Border.all(color: c.ink)),
      alignment: Alignment.center,
      child: Text(label, style: AppText.small.copyWith(color: c.ink, fontWeight: FontWeight.w700), maxLines: 1),
    );
  }
}

class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.initials, this.size = 40, this.color = AppColors.clay, this.ring = false, this.online = false});
  final String initials;
  final double size;
  final Color color;
  final bool ring;
  final bool online;
  @override
  Widget build(BuildContext context) {
    final circle = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: ring ? Border.all(color: AppColors.softHoney, width: 2) : null),
      alignment: Alignment.center,
      child: Text(initials, style: AppText.bodyStrong.copyWith(color: AppColors.white, fontSize: size * 0.36)),
    );
    if (!online) return ExcludeSemantics(child: circle);
    return ExcludeSemantics(
      child: Stack(clipBehavior: Clip.none, children: [
        circle,
        Positioned(
          right: 0,
          bottom: 0,
          child: Container(
            width: size * 0.28,
            height: size * 0.28,
            decoration: BoxDecoration(color: AppColors.fern, shape: BoxShape.circle, border: Border.all(color: AppColors.white, width: 2)),
          ),
        ),
      ]),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action, this.onAction, this.padding = const EdgeInsets.symmetric(horizontal: Insets.screen)});
  final String title;
  final String? action;
  final VoidCallback? onAction;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Row(
          children: [
            Expanded(child: Semantics(header: true, child: Text(title, style: AppText.section))),
            if (action != null)
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(minimumSize: const Size(44, 36), padding: const EdgeInsets.symmetric(horizontal: 6)),
                child: Text(action!),
              ),
          ],
        ),
      );
}

/// Teal (or other tone) note box with an icon.
class InfoNote extends StatelessWidget {
  const InfoNote(this.text, {super.key, this.icon = CraftIcons.info, this.tone = Tone.info, this.rich});
  final String text;
  final String icon;
  final Tone tone;
  final InlineSpan? rich;
  @override
  Widget build(BuildContext context) {
    final c = toneColors(tone);
    final bg = tone == Tone.seller ? AppColors.clayTint : c.tint;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: bg, borderRadius: Radii.field),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CraftIcon(icon, size: 18, color: c.ink),
        const SizedBox(width: 10),
        Expanded(child: rich != null ? Text.rich(rich!, style: AppText.body.copyWith(fontSize: 12.5, height: 1.45)) : Text(text, style: AppText.body.copyWith(fontSize: 12.5, height: 1.45))),
      ]),
    );
  }
}

/// Friendly empty state: icon, title, message and an optional action.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.message, this.actionLabel, this.onAction});
  final String icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 76,
            height: 76,
            decoration: const BoxDecoration(color: AppColors.lightSand, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: CraftIcon(icon, size: 34, color: AppColors.grayBrown),
          ),
          const SizedBox(height: 14),
          Text(title, style: AppText.section, textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(message, style: AppText.body.copyWith(color: AppColors.grayBrown, fontSize: 13.5), textAlign: TextAlign.center),
          if (actionLabel != null) ...[
            const SizedBox(height: 18),
            AppButton(label: actionLabel!, onPressed: onAction, expand: false, height: 46),
          ],
        ]),
      );
}

/// − 3 + stepper used for quantities.
class QuantityStepper extends StatelessWidget {
  const QuantityStepper({super.key, required this.value, required this.onChanged, this.min = 1, this.max = 100});
  final int value;
  final ValueChanged<int> onChanged;
  final int min;
  final int max;
  @override
  Widget build(BuildContext context) => Container(
        height: Insets.fieldHeight,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(color: AppColors.white, borderRadius: Radii.field, border: Border.all(color: AppColors.linen, width: 1.5)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            RoundIconButton(icon: CraftIcons.minus, tooltip: 'Decrease quantity', size: 34, onPressed: value > min ? () => onChanged(value - 1) : null),
            Semantics(label: 'Quantity $value', excludeSemantics: true, child: Text('$value', style: AppText.section.copyWith(fontWeight: FontWeight.w800))),
            RoundIconButton(icon: CraftIcons.plus, tooltip: 'Increase quantity', size: 34, onPressed: value < max ? () => onChanged(value + 1) : null),
          ],
        ),
      );
}

/// Dashed "Add a photo" box (photo upload is wired to Supabase Storage in Milestone 3).
class DashedAddBox extends StatelessWidget {
  const DashedAddBox({super.key, required this.label, required this.onTap, this.width, this.height = 64, this.vertical = false});
  final String label;
  final VoidCallback onTap;
  final double? width;
  final double height;
  final bool vertical;
  @override
  Widget build(BuildContext context) {
    final content = [
      const CraftIcon(CraftIcons.camera, size: 22, color: AppColors.clayText),
      SizedBox(width: vertical ? 0 : 8, height: vertical ? 4 : 0),
      Text(label, style: AppText.label.copyWith(color: AppColors.clayText, fontWeight: FontWeight.w700, fontSize: vertical ? 11.5 : 14)),
    ];
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: CustomPaint(
          painter: _DashedBorderPainter(),
          child: SizedBox(
            width: width,
            height: height,
            child: vertical
                ? Column(mainAxisAlignment: MainAxisAlignment.center, children: content)
                : Row(mainAxisAlignment: MainAxisAlignment.center, children: content),
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(14));
    canvas.drawRRect(rrect, Paint()..color = AppColors.white);
    final paint = Paint()
      ..color = AppColors.clay
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final path = Path()..addRRect(rrect.deflate(0.75));
    for (final metric in path.computeMetrics()) {
      double d = 0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 6), paint);
        d += 10;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

void showComingSoon(BuildContext context, String what) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text('$what will be connected in Milestone 3.')));
}

void showMessage(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}
