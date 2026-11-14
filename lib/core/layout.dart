import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

import 'theme.dart';

/// Layout helpers for large windows (desktop, tablets in landscape). On a phone
/// every one of them steps aside and lays its children out exactly as before.

/// Wide enough for a page to split into side-by-side panes.
const double kSplitBreakpoint = 900;

bool isWide(BuildContext context) => MediaQuery.sizeOf(context).width >= kSplitBreakpoint;

/// A phone or tablet, as opposed to a desktop: things like home-screen widgets,
/// haptics, volume-key paging and screen brightness only exist there.
final bool kMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);

/// Keeps [child] to a centred column at most [max] wide.
///
/// The child is told the screen is that wide, so anything that sizes itself from
/// the screen fits the column. A mouse wheel turned over the empty margins still
/// scrolls the page, as it would on any desktop app.
class PageWidth extends StatelessWidget {
  const PageWidth({super.key, this.max = 860, required this.child});

  final double max;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth <= max) return child;
      final mq = MediaQuery.of(context);
      final side = (c.maxWidth - max) / 2;
      return Listener(
        behavior: HitTestBehavior.translucent,
        onPointerSignal: (e) {
          if (e is! PointerScrollEvent) return;
          final x = e.localPosition.dx;
          if (x >= side && x <= side + max) return;
          // Hand the wheel to whatever is under the same height in the column.
          final left = e.position.dx - x;
          GestureBinding.instance.handlePointerEvent(e.copyWith(position: Offset(left + side + max / 2, e.position.dy)));
        },
        child: Center(
          child: SizedBox(
            width: max,
            child: MediaQuery(data: mq.copyWith(size: Size(max, mq.size.height)), child: child),
          ),
        ),
      );
    });
  }
}

/// A detail page (a book, an audiobook, a show). On a phone [side] and [main]
/// stack in one scrolling list; on a wide window [side] (cover, title, actions)
/// stands in its own column beside [main] (about, chapters, episodes).
class SplitDetail extends StatelessWidget {
  const SplitDetail({
    super.key,
    required this.side,
    required this.main,
    this.padding = const EdgeInsets.fromLTRB(20, 8, 20, 40),
    this.sideWidth = 380,
    this.controller,
  });

  final List<Widget> side;
  final List<Widget> main;

  /// Padding of the single list on a phone.
  final EdgeInsets padding;
  final double sideWidth;

  /// Drives the list holding [main] (or the whole list on a phone).
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    if (!isWide(context)) return ListView(controller: controller, padding: padding, children: [...side, ...main]);
    return PageWidth(
      max: 1560,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: sideWidth + 56,
          child: ListView(padding: const EdgeInsets.fromLTRB(32, 16, 24, 40), children: side),
        ),
        Container(width: 1, color: Tokens.of(context).line),
        Expanded(child: ListView(controller: controller, padding: const EdgeInsets.fromLTRB(32, 0, 32, 40), children: main)),
      ]),
    );
  }
}

/// A [GestureDetector] that shows the hand cursor while it can be tapped, as
/// buttons do on a desktop. A right-click does what a long press does, since a
/// mouse has no long press.
class Tap extends GestureDetector {
  Tap({super.key, super.child, super.onTap, super.onTapDown, super.onTapUp, super.onDoubleTap, super.onLongPress, VoidCallback? onSecondaryTap, super.behavior})
      : super(onSecondaryTap: onSecondaryTap ?? onLongPress);

  @override
  Widget build(BuildContext context) {
    final w = super.build(context);
    if (onTap == null && onDoubleTap == null && onLongPress == null) return w;
    return MouseRegion(cursor: SystemMouseCursors.click, child: w);
  }
}

/// Two columns on a wide window, one after the other on a phone. For content
/// inside a scroll view that already exists (where [SplitDetail] won't fit).
class SplitColumns extends StatelessWidget {
  const SplitColumns({super.key, required this.left, required this.right, this.leftWidth = 380, this.gap = 48});

  final List<Widget> left;
  final List<Widget> right;
  final double leftWidth;
  final double gap;

  @override
  Widget build(BuildContext context) {
    if (!isWide(context)) return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [...left, ...right]);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: leftWidth, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: left)),
      SizedBox(width: gap),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: right)),
    ]);
  }
}
