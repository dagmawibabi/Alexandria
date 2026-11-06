import 'dart:io';

import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/settings.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../models/annotations.dart';
import '../../models/doc.dart';
import '../../core/image_viewer.dart';

enum SelAction { highlight, unmark, bookmark, note, explain, define, quote, copy, find, speak }

typedef OnSelection = void Function(SelAction action, int block, int start, int end, String text, {int color});

/// Resolved typography and colours for the reading surface.
class ReaderStyle {
  ReaderStyle._(this.surface, this.body, this.paraGap, this.margin, this.align, this.indent, this.images, this.muted);

  factory ReaderStyle.of(Settings s, Surface surface, {double scale = 1}) {
    final body = GoogleFonts.getFont(
      s.fontFamily,
      fontSize: s.fontSize * scale,
      height: s.lineHeight,
      letterSpacing: s.letterSpacing,
      fontWeight: FontWeight.values[((s.fontWeight ~/ 100) - 1).clamp(0, 8)],
      color: surface.fg,
    );
    return ReaderStyle._(surface, body, s.paragraphSpacing * s.fontSize * scale, s.margin, s.justify ? TextAlign.justify : TextAlign.left, s.indentParagraphs, s.showImages,
        surface.fg.withValues(alpha: .55));
  }

  final Surface surface;
  final TextStyle body;
  final double paraGap;
  final double margin;
  final TextAlign align;
  final bool indent;
  final bool images;
  final Color muted;

  TextStyle heading(int level) => body.copyWith(
        fontSize: body.fontSize! * switch (level) { <= 1 => 1.65, 2 => 1.38, 3 => 1.18, _ => 1.05 },
        fontWeight: FontWeight.w700,
        height: 1.22,
        letterSpacing: -.3,
      );
}

class BlockView extends StatelessWidget {
  const BlockView({
    super.key,
    required this.block,
    required this.index,
    required this.style,
    required this.highlights,
    required this.onSelection,
    this.search,
    this.speaking = false,
    this.bookmarked = false,
  });

  final Block block;
  final int index;
  final ReaderStyle style;
  final List<Highlight> highlights;
  final OnSelection onSelection;
  final String? search;
  final bool speaking;
  final bool bookmarked;

  @override
  Widget build(BuildContext context) {
    final s = style;
    Widget child;
    switch (block.type) {
      case BlockType.image:
        if (!s.images || block.image == null) return const SizedBox.shrink();
        child = GestureDetector(
          onTap: () => _viewImage(context, block.image!),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * .6),
            child: Center(
              child: Image.file(File(block.image!), fit: BoxFit.contain, errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  color: s.surface.dark ? Colors.white.withValues(alpha: .88) : null, colorBlendMode: s.surface.dark ? BlendMode.modulate : null),
            ),
          ),
        );
      case BlockType.rule:
        child = Center(child: Text('· · ·', style: s.body.copyWith(color: s.muted, letterSpacing: 6)));
      case BlockType.heading:
        child = Padding(
          padding: EdgeInsets.only(top: s.paraGap * (block.level <= 2 ? 2.2 : 1.2), bottom: s.paraGap * .4),
          child: _text(context, s.heading(block.level), TextAlign.left, 0),
        );
      case BlockType.quote:
        child = Container(
          padding: const EdgeInsets.only(left: 16),
          decoration: BoxDecoration(border: Border(left: BorderSide(color: Settings.i.signalOn(s.surface.fg), width: 2))),
          child: _text(context, s.body.copyWith(fontStyle: FontStyle.italic, color: s.surface.fg.withValues(alpha: .8)), s.align, 0),
        );
      case BlockType.paragraph:
        child = _text(context, s.body, s.align, s.indent ? 1 : 0);
    }

    return Container(
      padding: EdgeInsets.fromLTRB(s.margin, 0, s.margin, s.paraGap),
      decoration: speaking ? BoxDecoration(border: Border(left: BorderSide(color: Settings.i.signalOn(s.surface.fg), width: 3))) : null,
      child: bookmarked
          ? Stack(clipBehavior: Clip.none, children: [
              child,
              Positioned(right: -s.margin + 4, top: 4, child: Icon(Icons.bookmark_sharp, size: 14, color: Settings.i.signalOn(s.surface.fg))),
            ])
          : child,
    );
  }

  /// [prefix] is the number of indent characters prepended (offset-corrected for selection).
  Widget _text(BuildContext context, TextStyle base, TextAlign align, int prefix) {
    final text = block.text;
    final spans = <InlineSpan>[];
    if (prefix > 0) spans.add(const TextSpan(text: ' '));

    // Paint ranges: highlights, then search hits.
    final marks = <(int, int, Color)>[
      for (final h in highlights) (h.start.clamp(0, text.length), h.end.clamp(0, text.length), highlightColor(h.color).withValues(alpha: style.surface.dark ? .38 : .55)),
    ];
    if (search != null && search!.length > 1) {
      final lower = text.toLowerCase();
      final q = search!.toLowerCase();
      var i = lower.indexOf(q);
      while (i >= 0) {
        marks.add((i, i + q.length, Settings.i.signalOn(style.surface.fg).withValues(alpha: .45)));
        i = lower.indexOf(q, i + q.length);
      }
    }
    marks.sort((a, b) => a.$1.compareTo(b.$1));

    var pos = 0;
    for (final (a, b, c) in marks) {
      if (b <= pos) continue;
      final start = a < pos ? pos : a;
      if (start > pos) spans.add(TextSpan(text: text.substring(pos, start)));
      spans.add(TextSpan(text: text.substring(start, b), style: TextStyle(backgroundColor: c)));
      pos = b;
    }
    if (pos < text.length) spans.add(TextSpan(text: text.substring(pos)));

    return SelectableText.rich(
      TextSpan(style: base, children: spans),
      textAlign: align,
      contextMenuBuilder: (ctx, state) {
        final value = state.textEditingValue;
        final sel = value.selection;
        final a = (sel.start - prefix).clamp(0, text.length);
        final b = (sel.end - prefix).clamp(0, text.length);
        final chosen = b > a ? text.substring(a, b) : '';
        final hit = highlights.where((h) => h.start < b && a < h.end).firstOrNull;
        return SelectionMenu(
          anchors: state.contextMenuAnchors,
          marked: hit?.color,
          onAction: (action, {int color = 0}) {
            state.hideToolbar();
            state.userUpdateTextEditingValue(value.copyWith(selection: TextSelection.collapsed(offset: sel.end)), SelectionChangedCause.toolbar);
            if (chosen.trim().isNotEmpty || action == SelAction.unmark) onSelection(action, index, a, b, chosen.trim(), color: color);
          },
        );
      },
    );
  }

  void _viewImage(BuildContext context, String path) => openImageViewer(context, path: path, title: 'Picture');

}

/// The industrial selection toolbar: highlight colours + actions.
class SelectionMenu extends StatelessWidget {
  const SelectionMenu({super.key, required this.anchors, required this.onAction, this.marked, this.compact = false});

  final TextSelectionToolbarAnchors anchors;
  final void Function(SelAction action, {int color}) onAction;

  /// Colour of an existing highlight under the selection, if any.
  final int? marked;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final top = MediaQuery.paddingOf(context).top + 8;
    final above = anchors.primaryAnchor - Offset(8, top + 6);
    final below = (anchors.secondaryAnchor ?? anchors.primaryAnchor) - Offset(8, top - 18);
    final fg = t.bg;
    final actions = <(SelAction, String)>[
      (SelAction.explain, 'Explain'),
      (SelAction.define, 'Define'),
      (SelAction.quote, 'Card'),
      (SelAction.note, 'Note'),
      (SelAction.copy, 'Copy'),
      if (!compact) (SelAction.find, 'Find'),
      (SelAction.speak, 'Speak'),
    ];

    Widget tapper(Widget child, VoidCallback f) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            haptic();
            f();
          },
          child: child,
        );

    return Padding(
      padding: EdgeInsets.fromLTRB(8, top, 8, 8),
      child: CustomSingleChildLayout(
        delegate: TextSelectionToolbarLayoutDelegate(anchorAbove: above, anchorBelow: below, fitsAbove: anchors.primaryAnchor.dy > top + 110),
        child: Material(
          type: MaterialType.transparency,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 336),
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
            decoration: BoxDecoration(
              color: t.ink,
              borderRadius: BorderRadius.circular(t.radius + 4),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .3), blurRadius: 18, offset: const Offset(0, 8))],
            ),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              // The swatches share whatever the icons leave, so the row always ends flush.
              SizedBox(
                width: 316,
                child: Row(children: [
                  for (var i = 0; i < highlightColors.length; i++)
                    Expanded(
                      child: tapper(
                        Container(
                          height: 30,
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(
                            color: highlightColors[i],
                            borderRadius: BorderRadius.circular(t.radius),
                            border: Border.all(color: marked == i ? fg : Colors.transparent, width: 2.5),
                          ),
                          child: marked == i ? Icon(Icons.check_sharp, size: 16, color: Colors.black.withValues(alpha: .7)) : null,
                        ),
                        () => onAction(SelAction.highlight, color: i),
                      ),
                    ),
                  Container(width: 1, height: 24, margin: const EdgeInsets.symmetric(horizontal: 4), color: fg.withValues(alpha: .2)),
                  if (marked != null) tapper(Padding(padding: const EdgeInsets.all(5), child: Icon(Icons.format_color_reset_outlined, size: 20, color: fg)), () => onAction(SelAction.unmark)),
                  tapper(Padding(padding: const EdgeInsets.all(5), child: Icon(Icons.bookmark_add_outlined, size: 20, color: fg)), () => onAction(SelAction.bookmark)),
                ]),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: 316,
                child: Row(children: [
                  for (final (a, l) in actions)
                    Expanded(
                      child: tapper(
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
                          child: Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(caps(l), maxLines: 1, style: mono(context, size: 10.5, color: a == SelAction.explain ? t.accent : fg, weight: FontWeight.w600)),
                            ),
                          ),
                        ),
                        () => onAction(a),
                      ),
                    ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
