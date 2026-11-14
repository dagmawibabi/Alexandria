import 'dart:io';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/book.dart';
import 'net_image.dart';
import 'settings.dart';
import 'layout.dart';
import 'theme.dart';

export 'layout.dart';

/// Greys out [child] (cover art) when the monochrome theme is on.
Widget monoImage(Widget child) {
  if (!Settings.i.mono) return child;
  return ColorFiltered(
    colorFilter: const ColorFilter.matrix([.2126, .7152, .0722, 0, 0, .2126, .7152, .0722, 0, 0, .2126, .7152, .0722, 0, 0, 0, 0, 0, 1, 0]),
    child: child,
  );
}

void haptic([bool heavy = false]) {
  if (!Settings.i.haptics) return;
  heavy ? HapticFeedback.mediumImpact() : HapticFeedback.selectionClick();
}

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(Settings.i.zen ? msg : msg.toUpperCase()), duration: const Duration(seconds: 2)));
}

/// Uppercase monospace label: the voice of the interface.
class Label extends StatelessWidget {
  const Label(this.text, {super.key, this.color, this.size = 10.5, this.weight = FontWeight.w500});

  final String text;
  final Color? color;
  final double size;
  final FontWeight weight;

  @override
  Widget build(BuildContext context) {
    // Zen: sentence case in the regular face.
    final zen = Tokens.of(context).zen;
    return Text(zen ? _sentence(text) : text.toUpperCase(), style: mono(context, size: size, color: color, weight: weight), maxLines: 1, overflow: TextOverflow.ellipsis);
  }

  /// 'NO RESULTS' becomes 'No results'; single all-caps words (EPUB, PDF) stay as they are.
  static String _sentence(String s) => !s.contains(' ') || s != s.toUpperCase() ? s : s[0] + s.substring(1).toLowerCase();
}

/// A page's technical kicker line ("SYSTEM / CONFIGURATION"). Zen has no use for it.
class Kicker extends StatelessWidget {
  const Kicker(this.text, {super.key, this.pip = 8});
  final String text;
  final double pip;

  @override
  Widget build(BuildContext context) {
    if (Tokens.of(context).zen) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [Pip(size: pip), Flexible(child: Label(text, size: 9.5))]));
  }
}

/// A screen's app-bar title: a tiny mono label, or in zen a normal readable title.
class AppTitle extends StatelessWidget {
  const AppTitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    if (t.zen) return Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.ink, fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -.2));
    return Label(text, color: t.ink);
  }
}

/// All caps in the industrial look, as written in zen.
String caps(String s) => Settings.i.zen ? s : s.toUpperCase();

/// The small accent square that marks a page's kicker line (hidden in zen).
class Pip extends StatelessWidget {
  const Pip({super.key, this.size = 8});
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    if (t.zen) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.only(right: 8), child: Container(width: size, height: size, color: t.accent));
  }
}

/// "01 — LIBRARY ............ trailing"
/// The "See all" link on a section header, with a generous tap area.
class SeeAll extends StatelessWidget {
  const SeeAll({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tap(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Label('See all', color: Tokens.of(context).accent, weight: FontWeight.w600)),
      );
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.index, this.title, {super.key, this.trailing, this.padding = const EdgeInsets.fromLTRB(20, 24, 20, 10)});

  final String index;
  final String title;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    if (t.zen) {
      return Padding(
        padding: padding.copyWith(top: padding.top + 4),
        child: Row(children: [
          Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.ink, fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -.2))),
          if (trailing != null) ...[const SizedBox(width: 10), trailing!],
        ]),
      );
    }
    return Padding(
      padding: padding,
      child: Row(children: [
        if (index.isNotEmpty) ...[Label(index, color: t.accent, weight: FontWeight.w700), const SizedBox(width: 10)],
        Label(title, color: t.ink, weight: FontWeight.w600),
        const SizedBox(width: 10),
        Expanded(child: Container(height: 1, color: t.line)),
        if (trailing != null) ...[const SizedBox(width: 10), trailing!],
      ]),
    );
  }
}

class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.color, this.onTap, this.border});

  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final VoidCallback? onTap;
  final Color? border;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final box = Container(
      padding: padding,
      decoration: t.zen
          ? BoxDecoration(
              color: color ?? t.surface,
              borderRadius: t.br,
              border: border == null ? null : Border.all(color: border!),
              boxShadow: t.dark ? null : [BoxShadow(color: Colors.black.withValues(alpha: .04), blurRadius: 16, offset: const Offset(0, 4))],
            )
          : BoxDecoration(color: color ?? t.surface, borderRadius: t.br, border: Border.all(color: border ?? t.line)),
      child: child,
    );
    if (onTap == null) return box;
    return Tap(behavior: HitTestBehavior.opaque, onTap: () {
      haptic();
      onTap!();
    }, child: box);
  }
}

/// Square, hairline-bordered tool button.
class ToolButton extends StatelessWidget {
  const ToolButton(this.icon, {super.key, this.onTap, this.label, this.active = false, this.size = 44, this.tooltip, this.color, this.onLongPress});

  final IconData icon;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? label;
  final bool active;
  final double size;
  final String? tooltip;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final fg = active ? t.onAccent : (color ?? t.ink);
    Widget w = Tap(
      behavior: HitTestBehavior.opaque,
      onTap: onTap == null
          ? null
          : () {
              haptic();
              onTap!();
            },
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: size,
        constraints: BoxConstraints(minWidth: size),
        padding: EdgeInsets.symmetric(horizontal: label == null ? 0 : 12),
        decoration: t.zen
            ? BoxDecoration(color: active ? t.accent : t.raised, borderRadius: BorderRadius.circular(12))
            : BoxDecoration(
                color: active ? t.accent : t.raised.withValues(alpha: t.dark ? 1 : .7),
                borderRadius: t.br,
                border: Border.all(color: active ? t.accent : t.line),
              ),
        child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 19, color: fg),
          if (label != null) ...[const SizedBox(width: 8), Label(label!, color: fg, weight: FontWeight.w600)],
        ]),
      ),
    );
    if (tooltip != null) w = Tooltip(message: tooltip!, child: w);
    return w;
  }
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton(this.label, {super.key, this.onTap, this.icon, this.expand = false, this.ghost = false});

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool expand;
  final bool ghost;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final fg = ghost ? t.ink : t.onAccent;
    return Opacity(
      opacity: onTap == null ? .4 : 1,
      child: Tap(
        onTap: onTap == null
            ? null
            : () {
                haptic(true);
                onTap!();
              },
        child: Container(
          height: 48,
          width: expand ? double.infinity : null,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: t.zen
              ? BoxDecoration(color: ghost ? t.raised : t.accent, borderRadius: BorderRadius.circular(12))
              : BoxDecoration(
                  color: ghost ? Colors.transparent : t.accent,
                  borderRadius: t.br,
                  border: Border.all(color: ghost ? t.ink : t.accent),
                ),
          child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
            if (icon != null) ...[Icon(icon, size: 18, color: fg), const SizedBox(width: 10)],
            Label(label, color: fg, weight: FontWeight.w700, size: 11.5),
          ]),
        ),
      ),
    );
  }
}

/// Segmented hardware switch.
class Segmented<T> extends StatelessWidget {
  const Segmented({super.key, required this.values, required this.labels, required this.value, required this.onChanged});

  final List<T> values;
  final List<String> labels;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      height: t.zen ? 40 : 38,
      padding: const EdgeInsets.all(3),
      decoration: t.zen
          ? BoxDecoration(color: t.raised, borderRadius: BorderRadius.circular(12))
          : BoxDecoration(color: t.bg, borderRadius: t.br, border: Border.all(color: t.line)),
      child: Row(children: [
        for (var i = 0; i < values.length; i++)
          Expanded(
            child: Tap(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                haptic();
                onChanged(values[i]);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                alignment: Alignment.center,
                decoration: t.zen
                    ? BoxDecoration(
                        color: values[i] == value ? t.surface : Colors.transparent,
                        borderRadius: BorderRadius.circular(9),
                        boxShadow: values[i] == value ? [BoxShadow(color: Colors.black.withValues(alpha: t.dark ? .3 : .08), blurRadius: 6, offset: const Offset(0, 1))] : null,
                      )
                    : BoxDecoration(
                        color: values[i] == value ? t.ink : Colors.transparent,
                        borderRadius: BorderRadius.circular(math.max(0, t.radius - 2)),
                      ),
                child: Label(labels[i], color: values[i] == value ? (t.zen ? t.ink : t.bg) : t.muted, weight: FontWeight.w600),
              ),
            ),
          ),
      ]),
    );
  }
}

/// A labelled slider with a numeric read-out.
class SliderRow extends StatelessWidget {
  const SliderRow({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
    this.format,
    this.icon,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String Function(double)? format;
  final ValueChanged<double> onChanged;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        if (icon != null) ...[Icon(icon, size: 16, color: t.muted), const SizedBox(width: 8)],
        SizedBox(width: 96, child: Label(label)),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: (v) {
              if (divisions != null) haptic();
              onChanged(v);
            },
          ),
        ),
        const SizedBox(width: 10),
        Container(
          width: 54,
          padding: const EdgeInsets.symmetric(vertical: 4),
          alignment: Alignment.center,
          decoration: t.zen ? null : BoxDecoration(color: t.bg, border: Border.all(color: t.line), borderRadius: t.br),
          child: Text(format?.call(value) ?? value.toStringAsFixed(1), style: mono(context, size: 11, color: t.ink, spacing: 0)),
        ),
      ]),
    );
  }
}

/// Rectangular toggle switch.
class Toggle extends StatelessWidget {
  const Toggle({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    if (t.zen) {
      return Switch(
        value: value,
        onChanged: (v) {
          haptic();
          onChanged(v);
        },
        activeTrackColor: t.accent,
        activeThumbColor: t.onAccent,
        inactiveTrackColor: t.raised,
        inactiveThumbColor: t.muted,
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      );
    }
    return Tap(
      onTap: () {
        haptic();
        onChanged(!value);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 46,
        height: 26,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: value ? t.accent : t.bg,
          borderRadius: BorderRadius.circular(t.radius + 1),
          border: Border.all(color: value ? t.accent : t.line),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 18,
            decoration: BoxDecoration(color: value ? t.onAccent : t.muted, borderRadius: BorderRadius.circular(math.max(0, t.radius - 1))),
          ),
        ),
      ),
    );
  }
}

class ToggleRow extends StatelessWidget {
  const ToggleRow({super.key, required this.label, required this.value, required this.onChanged, this.hint});

  final String label;
  final String? hint;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(color: t.ink, fontSize: 14.5, fontWeight: FontWeight.w500)),
            if (hint != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(hint!, style: TextStyle(color: t.muted, fontSize: 12.5))),
          ]),
        ),
        const SizedBox(width: 12),
        Toggle(value: value, onChanged: onChanged),
      ]),
    );
  }
}

class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.color, this.filled = false, this.onTap});

  final String text;
  final Color? color;
  final bool filled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final c = color ?? t.ink;
    return Tap(
      onTap: onTap == null
          ? null
          : () {
              haptic();
              onTap!();
            },
      // Center with factors of 1 hugs the chip, and centres it when a horizontal
      // list forces its children to the full row height.
      child: Center(
        widthFactor: 1,
        heightFactor: 1,
        child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.symmetric(horizontal: t.zen ? 12 : 10, vertical: t.zen ? 7 : 6),
        decoration: t.zen
            ? BoxDecoration(color: filled ? c : t.raised, borderRadius: BorderRadius.circular(9))
            : BoxDecoration(
                color: filled ? c : Colors.transparent,
                borderRadius: t.br,
                border: Border.all(color: filled ? c : t.line),
              ),
        child: Label(text, color: filled ? (c.computeLuminance() > .5 ? Colors.black : Colors.white) : c, weight: FontWeight.w600),
        ),
      ),
    );
  }
}

/// Dot-matrix backdrop, like a cutting mat.
class DotGrid extends StatelessWidget {
  const DotGrid({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!Settings.i.dotGrid || Settings.i.zen) return child;
    final t = Tokens.of(context);
    return CustomPaint(painter: _DotPainter(t.line.withValues(alpha: t.dark ? .7 : .9)), child: child);
  }
}

class _DotPainter extends CustomPainter {
  _DotPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    const step = 18.0;
    for (double y = 9; y < size.height; y += step) {
      for (double x = 9; x < size.width; x += step) {
        canvas.drawCircle(Offset(x, y), .8, p);
      }
    }
  }

  @override
  bool shouldRepaint(_DotPainter old) => old.color != color;
}

Future<T?> showSheet<T>(BuildContext context, {required Widget Function(BuildContext) builder, bool scroll = true, double maxHeight = .88}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    // A min width as well, or a sheet with short content shrinks to fit it.
    // On a wide window the sheet keeps to a readable width, centred.
    constraints: BoxConstraints(
      minWidth: isWide(context) ? 640 : MediaQuery.of(context).size.width,
      maxWidth: isWide(context) ? 640 : double.infinity,
      maxHeight: MediaQuery.of(context).size.height * maxHeight,
    ),
    builder: (ctx) {
      final t = Tokens.of(ctx);
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 10),
          Container(width: 36, height: 4, decoration: BoxDecoration(color: t.line, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 6),
          Flexible(child: scroll ? SingleChildScrollView(child: builder(ctx)) : builder(ctx)),
        ]),
      );
    },
  );
}

Future<String?> promptText(BuildContext context, {required String title, String initial = '', String hint = ''}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Label(title, color: Tokens.of(ctx).ink, size: 12),
      content: TextField(controller: c, autofocus: true, decoration: InputDecoration(hintText: hint), onSubmitted: (v) => Navigator.pop(ctx, v)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Label('Cancel')),
        TextButton(onPressed: () => Navigator.pop(ctx, c.text), child: Label('OK', color: Tokens.of(ctx).accent)),
      ],
    ),
  );
}

Future<bool> confirm(BuildContext context, String title, String body) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Label(title, color: Tokens.of(ctx).ink, size: 12),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Label('Cancel')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: Label('Confirm', color: Tokens.of(ctx).accent)),
      ],
    ),
  );
  return r ?? false;
}

/// A book cover: the real one if we have it, otherwise a generated
/// "spec sheet" cover in the industrial style.
class Cover extends StatelessWidget {
  const Cover(this.book, {super.key, this.width, this.showProgress = false});

  final Book book;
  final double? width;
  final bool showProgress;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final path = book.coverPath;
    final hasFile = fileExists(path);
    return AspectRatio(
      aspectRatio: 2 / 3,
      child: Container(
        width: width,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: t.zen ? BorderRadius.circular(10) : t.br,
          border: t.zen ? null : Border.all(color: t.line),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: t.dark ? .5 : (t.zen ? .1 : .12)), blurRadius: t.zen ? 18 : 14, offset: const Offset(0, 6))],
        ),
        child: Stack(fit: StackFit.expand, children: [
          monoImage(hasFile ? SizedFileImage(File(path!), errorBuilder: (_, _, _) => GeneratedCover(book)) : GeneratedCover(book)),
          // spine shading
          if (!t.zen) Positioned(left: 0, top: 0, bottom: 0, width: 6, child: Container(color: Colors.black.withValues(alpha: .12))),
          if (showProgress && book.progress > 0)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 3,
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: book.progress.clamp(0, 1),
                child: Container(color: t.accent),
              ),
            ),
        ]),
      ),
    );
  }
}

class GeneratedCover extends StatelessWidget {
  const GeneratedCover(this.book, {super.key});
  final Book book;

  static const _palette = [
    Color(0xFF1D1D1B), Color(0xFFD9D6CE), Color(0xFFFF5A1F), Color(0xFF2D6BFF), //
    Color(0xFF3A4A3F), Color(0xFFB8B2A3), Color(0xFF8C2F1E), Color(0xFFFFC300),
  ];

  /// Soft tones for zen covers.
  static const _zenPalette = [
    Color(0xFFE8E2D6), Color(0xFFD6E2DC), Color(0xFFDCDDEB), Color(0xFFEBDCDC), //
    Color(0xFF2E3138), Color(0xFFE6E0EE), Color(0xFFD9E6EC), Color(0xFF3A3530),
  ];

  @override
  Widget build(BuildContext context) {
    final h = book.title.hashCode.abs();
    if (Tokens.of(context).zen) {
      final bg = _zenPalette[h % _zenPalette.length];
      final fg = bg.computeLuminance() > .45 ? const Color(0xFF26262B) : const Color(0xFFF4F4F5);
      return Container(
        color: bg,
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(builder: (context, c) {
          final scale = (c.maxWidth / 120).clamp(.6, 2.0);
          return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.end, children: [
            Flexible(child: Text(book.title, maxLines: 4, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontSize: 14 * scale, height: 1.15, fontWeight: FontWeight.w600))),
            if (book.author.isNotEmpty && c.maxHeight > 60 * scale) ...[
              SizedBox(height: 4 * scale),
              Text(book.author, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg.withValues(alpha: .7), fontSize: 9.5 * scale)),
            ],
          ]);
        }),
      );
    }
    final bg = _palette[h % _palette.length];
    final fg = bg.computeLuminance() > .45 ? const Color(0xFF151515) : const Color(0xFFF2F0EA);
    return Container(
      color: bg,
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
      child: LayoutBuilder(builder: (context, c) {
        final scale = (c.maxWidth / 120).clamp(.6, 2.0);
        // Thumbnails and square audio art don't have the room for everything:
        // the title stays, and the rest goes as the space runs out.
        final short = c.maxHeight < 100 * scale;
        final tiny = c.maxHeight < 60 * scale;
        return ClipRect(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (!short) ...[
              Row(children: [
                Expanded(child: Text(book.formatLabel, maxLines: 1, overflow: TextOverflow.clip, softWrap: false, style: monoFont(color: fg.withValues(alpha: .7), fontSize: 8 * scale, letterSpacing: 1))),
                Text('№${(h % 999).toString().padLeft(3, '0')}', style: monoFont(color: fg.withValues(alpha: .7), fontSize: 8 * scale)),
              ]),
              SizedBox(height: 6 * scale),
              Container(height: 1, color: fg.withValues(alpha: .4)),
            ],
            Expanded(
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Text(
                  book.title,
                  maxLines: tiny ? 3 : 4,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.spaceGrotesk(color: fg, fontSize: 15 * scale, height: 1.05, fontWeight: FontWeight.w700, letterSpacing: -.3),
                ),
              ),
            ),
            if (!tiny && book.author.isNotEmpty) ...[
              SizedBox(height: 6 * scale),
              Text(book.author.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: monoFont(color: fg.withValues(alpha: .75), fontSize: 7.5 * scale, letterSpacing: .8)),
            ],
            if (!short) ...[
              SizedBox(height: 8 * scale),
              // barcode strip, clipped to whatever width the cover has
              SizedBox(
                height: 10 * scale,
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.centerLeft,
                    maxWidth: double.infinity,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      for (var i = 0; i < 22; i++)
                        Container(width: ((h >> (i % 16)) & 1) == 1 ? 2 : 1, margin: const EdgeInsets.only(right: 1.5), color: fg.withValues(alpha: .7)),
                    ]),
                  ),
                ),
              ),
            ],
          ]),
        );
      }),
    );
  }
}

String fmtDuration(int seconds, {bool short = false}) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  if (h > 0) return short ? '${h}h${m.toString().padLeft(2, '0')}' : '${h}h ${m}m';
  if (m > 0) return '${m}m';
  return '${seconds}s';
}

Color highlightColor(int i) => highlightColors[i.clamp(0, highlightColors.length - 1)];

String pad(int n, [int w = 2]) => n.toString().padLeft(w, '0');

/// Long text that starts clipped to [lines], with a Read more / Collapse switch.
class CollapsibleText extends StatefulWidget {
  const CollapsibleText(this.text, {super.key, this.style, this.lines = 6});

  final String text;
  final TextStyle? style;
  final int lines;

  @override
  State<CollapsibleText> createState() => _CollapsibleTextState();
}

class _CollapsibleTextState extends State<CollapsibleText> {
  bool _open = false;

  void _toggle() {
    haptic();
    setState(() => _open = !_open);
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final style = DefaultTextStyle.of(context).style.merge(widget.style);
    return LayoutBuilder(builder: (context, c) {
      final painter = TextPainter(
        text: TextSpan(text: widget.text, style: style),
        maxLines: widget.lines,
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(maxWidth: c.maxWidth);
      final long = painter.didExceedMaxLines;
      painter.dispose();
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // The text itself is a toggle too, not just the button under it.
        Tap(
          behavior: HitTestBehavior.opaque,
          onTap: long ? _toggle : null,
          child: AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: Text(widget.text, style: style, maxLines: _open || !long ? null : widget.lines, overflow: _open || !long ? null : TextOverflow.fade),
          ),
        ),
        if (long)
          Tap(
            behavior: HitTestBehavior.opaque,
            onTap: _toggle,
            child: Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Label(_open ? 'Collapse' : 'Read more', color: t.accent, weight: FontWeight.w600),
                const SizedBox(width: 4),
                Icon(_open ? Icons.keyboard_arrow_up_sharp : Icons.keyboard_arrow_down_sharp, size: 16, color: t.accent),
              ]),
            ),
          ),
      ]);
    });
  }
}

/// 1 to 5, tap the current value to clear.
class RatingBar extends StatelessWidget {
  const RatingBar({super.key, required this.value, required this.onChanged, this.size = 22});
  final int value;
  final ValueChanged<int> onChanged;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 1; i <= 5; i++)
        Tap(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            haptic();
            onChanged(value == i ? 0 : i);
          },
          child: Padding(
            padding: const EdgeInsets.only(right: 3),
            child: t.zen
                ? Icon(i <= value ? Icons.star_rounded : Icons.star_outline_rounded, size: size + 3, color: i <= value ? t.accent : t.muted)
                : Icon(i <= value ? Icons.square_sharp : Icons.crop_square_sharp, size: size, color: i <= value ? t.accent : t.muted),
          ),
        ),
    ]);
  }
}

/// A setting with room to read it: a title, what it does, a big value,
/// and a slider with exact +/- steps.
class SettingSlider extends StatelessWidget {
  const SettingSlider({super.key, required this.title, this.hint, required this.value, required this.min, required this.max, required this.onChanged, this.step = 1, this.unit = ''});

  final String title;
  final String? hint;
  final int value;
  final int min;
  final int max;
  final int step;
  final String unit;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    void go(int v) => onChanged(v.clamp(min, max));
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Panel(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600)),
                if (hint != null) Padding(padding: const EdgeInsets.only(top: 3), child: Text(hint!, style: TextStyle(color: t.muted, fontSize: 13.5, height: 1.3))),
              ]),
            ),
            const SizedBox(width: 12),
            Text('$value', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: t.accent, height: 1)),
            if (unit.isNotEmpty) Padding(padding: const EdgeInsets.only(left: 4, top: 10), child: Text(unit, style: TextStyle(color: t.muted, fontSize: 13))),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            ToolButton(Icons.remove_sharp, size: 40, onTap: value <= min ? null : () => go(value - step)),
            const SizedBox(width: 10),
            Expanded(
              child: Slider(
                value: value.toDouble().clamp(min.toDouble(), max.toDouble()),
                min: min.toDouble(),
                max: max.toDouble(),
                divisions: (max - min) ~/ step,
                onChanged: (v) {
                  haptic();
                  go(v.round());
                },
              ),
            ),
            const SizedBox(width: 10),
            ToolButton(Icons.add_sharp, size: 40, onTap: value >= max ? null : () => go(value + step)),
          ]),
        ]),
      ),
    );
  }
}

/// An on/off setting with room to read it.
class SettingToggle extends StatelessWidget {
  const SettingToggle({super.key, required this.title, this.hint, required this.value, required this.onChanged});
  final String title;
  final String? hint;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Panel(
        onTap: () => onChanged(!value),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600)),
              if (hint != null) Padding(padding: const EdgeInsets.only(top: 3), child: Text(hint!, style: TextStyle(color: t.muted, fontSize: 13.5, height: 1.3))),
            ]),
          ),
          const SizedBox(width: 12),
          Toggle(value: value, onChanged: onChanged),
        ]),
      ),
    );
  }
}
