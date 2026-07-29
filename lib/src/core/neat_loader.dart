import 'package:flutter/material.dart';

/// Branded loading indicator: the Neat logo gently pulsing (scale + fade) so it
/// reads as "loading" instead of a generic spinner.
///
/// Deliberately cheap — a single AnimationController driving one decoded-to-size
/// cached image — so it can stand in for the primary full-screen spinners with
/// no meaningful performance cost. It is intentionally NOT used for per-image
/// placeholders, where many loaders can be on screen at once (each would need
/// its own controller); those keep a plain spinner.
class NeatLoader extends StatefulWidget {
  const NeatLoader({super.key, this.size = 68, this.color});

  final double size;

  /// Overrides the tint. The logo asset is white, so by default it is painted
  /// in the theme's foreground — black on the light scaffold, where an
  /// untinted white logo was simply invisible. Pass this only for surfaces
  /// that stay dark regardless of theme, such as the city card.
  final Color? color;

  @override
  State<NeatLoader> createState() => _NeatLoaderState();
}

class _NeatLoaderState extends State<NeatLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1050),
  )..repeat(reverse: true);

  late final Animation<double> _curve =
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final decodeWidth =
        (widget.size * MediaQuery.devicePixelRatioOf(context)).round();
    final tint = widget.color ??
        (Theme.of(context).brightness == Brightness.light
            ? Colors.black
            : Colors.white);
    return Center(
      child: FadeTransition(
        opacity: Tween<double>(begin: 0.45, end: 1.0).animate(_curve),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.82, end: 1.0).animate(_curve),
          child: Image.asset(
            'assets/neat_logo.png',
            width: widget.size,
            height: widget.size,
            cacheWidth: decodeWidth,
            color: tint,
            colorBlendMode: BlendMode.srcIn,
          ),
        ),
      ),
    );
  }
}
