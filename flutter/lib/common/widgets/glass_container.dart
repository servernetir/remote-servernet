import 'dart:ui';

import 'package:flutter/material.dart';

/// Frosted-glass panel: blurred backdrop + translucent tint + soft border.
/// Used as the base building block for the "glassy" desktop/mobile theme.
class GlassContainer extends StatelessWidget {
  const GlassContainer({
    Key? key,
    required this.child,
    this.borderRadius = 18,
    // sigma 20 is a very expensive backdrop pass and is indistinguishable from
    // 8 over a low-frequency aurora. Keep it low: this widget can be on screen
    // while the GPU is already busy decoding a remote video stream.
    this.blurSigma = 8,
    this.padding,
    this.margin,
    this.width,
    this.height,
    this.tint,
    this.opacity,
    this.borderColor,
    this.borderWidth = 1,
    this.gradient,
    this.boxShadow,
    this.alignment,
  }) : super(key: key);

  final Widget child;
  final double borderRadius;
  final double blurSigma;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;
  final Color? tint;
  final double? opacity;
  final Color? borderColor;
  final double borderWidth;
  final Gradient? gradient;
  final List<BoxShadow>? boxShadow;
  final AlignmentGeometry? alignment;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // servernet.cloud glass recipe: --surface over --bg, hairline --line border.
    final resolvedTint = tint ?? (isDark ? const Color(0xFF05070F) : Colors.white);
    final resolvedOpacity = opacity ?? (isDark ? 0.72 : 0.74);
    final resolvedBorder = borderColor ??
        (isDark
            ? Colors.white.withOpacity(0.14)
            : const Color(0xFF0F172A).withOpacity(0.17));

    return Container(
      width: width,
      height: height,
      margin: margin,
      alignment: alignment,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: gradient == null ? resolvedTint.withOpacity(resolvedOpacity) : null,
              gradient: gradient,
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(color: resolvedBorder, width: borderWidth),
              boxShadow: boxShadow ??
                  [
                    BoxShadow(
                      color: Colors.black.withOpacity(isDark ? 0.35 : 0.10),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Soft multi-color mesh-gradient backdrop meant to sit behind glass panels
/// so the blur effect has something to work with.
class GlassBackdrop extends StatelessWidget {
  const GlassBackdrop({Key? key, this.child}) : super(key: key);

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            // Ground tones lifted verbatim from servernet.cloud (--bg / --bg2).
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? const [
                      Color(0xFF05070F),
                      Color(0xFF080B16),
                      Color(0xFF0A0D18),
                    ]
                  : const [
                      Color(0xFFF3F5FB),
                      Color(0xFFF7F9FD),
                      Color(0xFFEFF3FB),
                    ],
            ),
          ),
        ),
        // Brand aurora: blue -> cyan -> violet, the servernet.cloud accent trio.
        Positioned(
          top: -170,
          left: -140,
          child: _blob(const Color(0xFF3B82F6), 420, isDark),
        ),
        Positioned(
          top: -90,
          right: -130,
          child: _blob(const Color(0xFF22D3EE), 360, isDark),
        ),
        Positioned(
          bottom: -180,
          right: -120,
          child: _blob(const Color(0xFF8B5CF6), 440, isDark),
        ),
        if (child != null) child!,
      ],
    );
  }

  Widget _blob(Color color, double size, bool isDark) {
    // A radial falloff, not a flat disc. A solid circle at 22% reads as a
    // hard-edged pastel blob; the gradient gives the same soft glow the brand
    // site gets from a 70px CSS blur, without paying for an ImageFilter pass.
    //
    // Four stops rather than three: the extra one near the centre keeps the
    // core luminous while the tail still reaches zero, so the edge never shows
    // the faint ring a two-step ramp leaves behind.
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withOpacity(isDark ? 0.40 : 0.20),
              color.withOpacity(isDark ? 0.26 : 0.12),
              color.withOpacity(isDark ? 0.09 : 0.04),
              color.withOpacity(0.0),
            ],
            stops: const [0.0, 0.38, 0.68, 1.0],
          ),
        ),
      ),
    );
  }
}
