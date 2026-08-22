import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// Liquid-glass design tokens (PRD §16). These are the final numbers — every
/// glass surface in the app reads from here; adjust taste in one place only.
abstract final class GlassTokens {
  /// Fill: 10% of surface-tint over the background.
  static const double fillOpacity = 0.10;

  /// Background blur strength.
  static const double blurSigma = 20.0;

  /// Hairline border: ~12% of onSurface.
  static const double borderOpacity = 0.12;

  /// Corner radius for large hero surfaces.
  static const double heroRadius = 28.0;

  /// Corner radius for cards and control groups.
  static const double controlRadius = 20.0;
}

/// A restrained liquid-glass surface: translucent tinted fill, hairline
/// border, optional background blur. No elevation — depth comes from blur
/// and border alone (PRD §16).
///
/// Use [blur] sparingly: enable it only where animated or colorful content
/// actually sits behind the surface; flat backgrounds gain little from the
/// filter's GPU cost.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    required this.child,
    this.borderRadius = GlassTokens.controlRadius,
    this.blur = true,
    this.padding,
    super.key,
  });

  final Widget child;
  final double borderRadius;
  final bool blur;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(borderRadius);
    // A Material ancestor is required so descendant ListTiles/InkWells paint
    // their background and splashes above the glass fill.
    final surface = Material(
      type: MaterialType.canvas,
      color:
          colorScheme.surfaceTint.withValues(alpha: GlassTokens.fillOpacity),
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(
          width: 1,
          color:
              colorScheme.onSurface.withValues(alpha: GlassTokens.borderOpacity),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: padding ?? EdgeInsets.zero,
        child: child,
      ),
    );
    if (!blur) return surface;
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: GlassTokens.blurSigma,
          sigmaY: GlassTokens.blurSigma,
        ),
        child: surface,
      ),
    );
  }
}
