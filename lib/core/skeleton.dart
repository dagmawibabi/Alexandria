import 'package:material_ui/material_ui.dart';

import 'theme.dart';

// Loading placeholders shaped like what's coming, in place of a lone spinner:
// the page keeps its layout, and the content lands where the eye already is.

/// Sweeps a soft highlight across every [Bone] inside it, all in step. One
/// animation for the whole view, and none at all with reduce motion on.
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child, this.color});
  final Widget child;

  /// The bones' colour; defaults to a faint wash of the ink colour.
  final Color? color;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final base = widget.color ?? t.ink.withValues(alpha: t.dark ? .09 : .07);
    // The sweep reads as light passing over: brighter on dark, paler on light.
    final glow = widget.color != null ? widget.color!.withValues(alpha: widget.color!.a * .45) : t.ink.withValues(alpha: t.dark ? .16 : .03);
    return Semantics(
      label: 'Loading',
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: _c,
          child: widget.child,
          builder: (context, child) => ShaderMask(
            // The gradient's own colour (and alpha) wherever a bone is; the
            // bones' paint only marks the shape.
            blendMode: BlendMode.srcIn,
            shaderCallback: (r) {
              // The band travels from off the left edge to off the right.
              final x = -1.5 + _c.value * 3;
              return LinearGradient(
                begin: Alignment(x - 1, -.3),
                end: Alignment(x + 1, .3),
                colors: [base, glow, base],
                stops: const [.3, .5, .7],
              ).createShader(r);
            },
            child: child,
          ),
        ),
      ),
    );
  }
}

/// One placeholder block. Its own colour is replaced by the [Shimmer]'s.
class Bone extends StatelessWidget {
  const Bone({super.key, this.width, this.height = 12, this.radius, this.square = false});

  /// Null fills the width it's given.
  final double? width;
  final double height;
  final double? radius;

  /// A square as wide as it's given (cover art).
  final bool square;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final box = DecoratedBox(decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(radius ?? (t.zen ? 8 : (t.radius > 4 ? 4 : t.radius)))));
    if (square) return AspectRatio(aspectRatio: 1, child: box);
    return SizedBox(width: width, height: height, child: box);
  }
}

/// A line of text-to-be, as a fraction of the width available.
class _Line extends StatelessWidget {
  const _Line(this.fraction, {this.height = 11});
  final double fraction;
  final double height;

  @override
  Widget build(BuildContext context) => FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: fraction, child: Bone(height: height));
}

/// Rows like a results list: optional art, then a title and a line or two.
class SkeletonRows extends StatelessWidget {
  const SkeletonRows({super.key, this.count = 6, this.art = 56, this.artAspect = 1, this.lines = 2, this.padding = EdgeInsets.zero, this.dividers = true});
  final int count;

  /// The art's width; null for rows without art.
  final double? art;

  /// Width / height of the art (2/3 for book covers).
  final double artAspect;
  final int lines;
  final EdgeInsets padding;
  final bool dividers;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    // Vary the widths a little, so it reads as text rather than a grid of bars.
    const widths = [.82, .64, .9, .7, .76, .58];
    return Shimmer(
      child: Padding(
        padding: padding,
        child: Column(children: [
          for (var i = 0; i < count; i++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: dividers && i < count - 1 ? BoxDecoration(border: Border(bottom: BorderSide(color: t.line))) : null,
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (art != null) ...[
                  SizedBox(width: art, child: AspectRatio(aspectRatio: artAspect, child: const Bone(height: double.infinity))),
                  const SizedBox(width: 14),
                ],
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _Line(widths[i % widths.length], height: 13),
                      for (var l = 1; l < lines; l++) ...[const SizedBox(height: 8), _Line(widths[(i + l * 2) % widths.length] * .6, height: 9)],
                    ]),
                  ),
                ),
              ]),
            ),
        ]),
      ),
    );
  }
}

/// Tiles like a cover grid: art, then a title and a caption.
class SkeletonGrid extends StatelessWidget {
  const SkeletonGrid({super.key, this.count = 9, this.columns = 3, this.padding = EdgeInsets.zero});
  final int count;
  final int columns;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: Padding(
        padding: padding,
        child: LayoutBuilder(builder: (context, c) {
          const gap = 12.0;
          final w = (c.maxWidth - gap * (columns - 1)) / columns;
          return Wrap(spacing: gap, runSpacing: 16, children: [
            for (var i = 0; i < count; i++)
              SizedBox(
                width: w,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Bone(square: true),
                  const SizedBox(height: 8),
                  _Line(i.isEven ? .9 : .75, height: 10),
                  const SizedBox(height: 6),
                  _Line(i % 3 == 0 ? .5 : .4, height: 8),
                ]),
              ),
          ]);
        }),
      ),
    );
  }
}

/// A paragraph or a few: lines of varied length, the last of each shorter.
class SkeletonText extends StatelessWidget {
  const SkeletonText({super.key, this.lines = 5, this.paragraphs = 1, this.lineHeight = 11, this.gap = 10, this.color});
  final int lines;
  final int paragraphs;
  final double lineHeight;
  final double gap;

  /// For surfaces with their own colours (the reader's page).
  final Color? color;

  @override
  Widget build(BuildContext context) {
    const widths = [.96, .92, .98, .88, .94, .9];
    return Shimmer(
      color: color,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var p = 0; p < paragraphs; p++) ...[
          if (p > 0) SizedBox(height: gap * 2.2),
          for (var i = 0; i < lines; i++) ...[
            if (i > 0) SizedBox(height: gap),
            _Line(i == lines - 1 ? .55 + (p % 3) * .1 : widths[(i + p) % widths.length], height: lineHeight),
          ],
        ],
      ]),
    );
  }
}
