import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../fieldpulse_theme.dart';

class FieldPulseSectionHeader extends StatelessWidget {
  const FieldPulseSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
      ?trailing,
    ],
  );
}

class FieldPulseIconBadge extends StatelessWidget {
  const FieldPulseIconBadge({
    super.key,
    required this.icon,
    this.color = FieldPulseTheme.blue,
    this.size = 44,
  });

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [color.withValues(alpha: .17), color.withValues(alpha: .065)],
      ),
      borderRadius: BorderRadius.circular(size * .32),
      border: Border.all(color: color.withValues(alpha: .15)),
      boxShadow: [
        BoxShadow(
          color: color.withValues(alpha: .10),
          blurRadius: 14,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    child: Icon(icon, color: color, size: size * .48),
  );
}

class FieldPulseStatusPill extends StatelessWidget {
  const FieldPulseStatusPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .10),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color.withValues(alpha: .18)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
        ],
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class FieldPulseHeroCard extends StatelessWidget {
  const FieldPulseHeroCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      gradient: FieldPulseDecor.appGradient,
      borderRadius: BorderRadius.circular(28),
      border: Border.all(color: Colors.white.withValues(alpha: .10)),
      boxShadow: FieldPulseDecor.premiumShadow,
    ),
    child: Stack(
      children: [
        Positioned(
          top: -54,
          right: -34,
          child: Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: .055),
            ),
          ),
        ),
        Positioned(
          bottom: -74,
          left: -42,
          child: Container(
            width: 180,
            height: 180,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: FieldPulseTheme.cyan.withValues(alpha: .07),
            ),
          ),
        ),
        Padding(padding: padding, child: child),
      ],
    ),
  );
}

class FieldPulseInfoCard extends StatelessWidget {
  const FieldPulseInfoCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      gradient: FieldPulseDecor.premiumSurfaceGradient,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: Colors.white),
      boxShadow: FieldPulseDecor.softShadow,
    ),
    child: Padding(padding: padding, child: child),
  );
}

class FieldPulsePageBackground extends StatelessWidget {
  const FieldPulsePageBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(gradient: FieldPulseDecor.pageGradient),
    child: Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          child: Align(
            alignment: const Alignment(1.25, -1.15),
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    FieldPulseTheme.cyan.withValues(alpha: .10),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
        IgnorePointer(
          child: Align(
            alignment: const Alignment(-1.25, .95),
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    FieldPulseTheme.blue.withValues(alpha: .075),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
        child,
      ],
    ),
  );
}

class FieldPulseGlassCard extends StatefulWidget {
  const FieldPulseGlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.only(bottom: 12),
    this.onTap,
    this.tint,
  });

  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets margin;
  final VoidCallback? onTap;
  final Color? tint;

  @override
  State<FieldPulseGlassCard> createState() => _FieldPulseGlassCardState();
}

class _FieldPulseGlassCardState extends State<FieldPulseGlassCard> {
  var _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.tint ?? FieldPulseTheme.blue;
    final decoration = BoxDecoration(
      gradient: FieldPulseDecor.glassGradient,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: Colors.white.withValues(alpha: .94)),
      boxShadow: FieldPulseDecor.glassShadow,
    );

    final content = Ink(
      decoration: decoration,
      child: Padding(padding: widget.padding, child: widget.child),
    );

    return AnimatedScale(
      scale: widget.onTap == null || !_pressed ? 1 : .985,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOutCubic,
      child: Container(
        margin: widget.margin,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: widget.onTap == null
              ? content
              : InkWell(
                  onTapDown: (_) => _setPressed(true),
                  onTapCancel: () => _setPressed(false),
                  onTapUp: (_) => _setPressed(false),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    widget.onTap?.call();
                  },
                  splashColor: accent.withValues(alpha: .075),
                  highlightColor: accent.withValues(alpha: .035),
                  child: content,
                ),
        ),
      ),
    );
  }
}

class FieldPulseGlassPanel extends StatelessWidget {
  const FieldPulseGlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.blur = 16,
  });

  final Widget child;
  final EdgeInsets padding;
  final double blur;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(24),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
      child: Container(
        decoration: BoxDecoration(
          gradient: FieldPulseDecor.glassGradient,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: .92)),
          boxShadow: FieldPulseDecor.glassShadow,
        ),
        child: Padding(padding: padding, child: child),
      ),
    ),
  );
}

class FieldPulseMetricTile extends StatelessWidget {
  const FieldPulseMetricTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.color = FieldPulseTheme.blue,
    this.caption,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final String? caption;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      gradient: FieldPulseDecor.glassGradient,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: Colors.white.withValues(alpha: .94)),
      boxShadow: FieldPulseDecor.glassShadow,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldPulseIconBadge(icon: icon, color: color, size: 40),
        const SizedBox(height: 14),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontSize: 23, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 3),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        if (caption != null) ...[
          const SizedBox(height: 7),
          Text(
            caption!,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ],
    ),
  );
}

class FieldPulsePremiumLoading extends StatelessWidget {
  const FieldPulsePremiumLoading({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 42),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: FieldPulseDecor.accentGradient,
              borderRadius: BorderRadius.circular(18),
              boxShadow: FieldPulseDecor.softShadow,
            ),
            child: const CircularProgressIndicator(
              strokeWidth: 2.4,
              color: Colors.white,
            ),
          ),
          if (label != null) ...[
            const SizedBox(height: 14),
            Text(label!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    ),
  );
}

class FieldPulseEmptyState extends StatelessWidget {
  const FieldPulseEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 28),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Container(
          padding: const EdgeInsets.fromLTRB(26, 30, 26, 26),
          decoration: BoxDecoration(
            gradient: FieldPulseDecor.glassGradient,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withValues(alpha: .95)),
            boxShadow: FieldPulseDecor.glassShadow,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FieldPulseIconBadge(icon: icon, size: 64),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -.2),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: FieldPulseTheme.muted, height: 1.45),
              ),
              if (action != null) ...[const SizedBox(height: 20), action!],
            ],
          ),
        ),
      ),
    ),
  );
}
