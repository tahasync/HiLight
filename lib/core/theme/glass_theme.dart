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
/// border. No elevation — depth comes from fill and border alone (PRD §16).
///
/// BackdropFilter blur is deliberately OFF everywhere: measured jank on
/// every scrollable surface (each frame paid a full-area GPU blur). The
/// [blur] flag remains for API compatibility but is ignored — revisit only
/// with a static, non-scrolling backdrop.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    required this.child,
    this.borderRadius = GlassTokens.controlRadius,
    this.blur = false,
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
    return surface;
  }
}
