import 'dart:ui';

import 'package:flutter/material.dart';

/// Frosted-glass panel: blurred backdrop + translucent tint + soft border.
/// Used as the base building block for the "glassy" desktop/mobile theme.
class GlassContainer extends StatelessWidget {
  const GlassContainer({
    Key? key,
    required this.child,
    this.borderRadius = 16,
    this.blurSigma = 20,
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
    final resolvedTint = tint ?? (isDark ? const Color(0xFF15171F) : Colors.white);
    final resolvedOpacity = opacity ?? (isDark ? 0.38 : 0.55);
    final resolvedBorder = borderColor ??
        (isDark
            ? Colors.white.withOpacity(0.08)
            : Colors.white.withOpacity(0.55));

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
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? const [
                      Color(0xFF0A0F1A),
                      Color(0xFF121A2E),
                      Color(0xFF12132A),
                    ]
                  : const [
                      Color(0xFFEAF2FF),
                      Color(0xFFE3EAFA),
                      Color(0xFFEFEAFB),
                    ],
            ),
          ),
        ),
        Positioned(
          top: -140,
          left: -110,
          child: _blob(const Color(0xFF5FD8CC), 380, isDark),
        ),
        Positioned(
          top: -60,
          right: -120,
          child: _blob(const Color(0xFF6FB6F5), 320, isDark),
        ),
        Positioned(
          bottom: -160,
          right: -110,
          child: _blob(const Color(0xFF8E9BF5), 420, isDark),
        ),
        if (child != null) child!,
      ],
    );
  }

  Widget _blob(Color color, double size, bool isDark) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(isDark ? 0.22 : 0.30),
      ),
    );
  }
}
