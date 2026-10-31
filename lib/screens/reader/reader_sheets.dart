import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';
import 'package:omni_ai/omni_ai.dart' show DeviceSpeech;
import 'package:screen_brightness/screen_brightness.dart';

import '../../core/color_picker.dart';
import '../../core/net_image.dart';
import '../../core/settings.dart';
import '../../core/search_box.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../models/annotations.dart';
import '../../models/book.dart';
import '../../models/doc.dart';
import '../../services/library.dart';
import '../../services/metadata.dart';
import '../../services/speech.dart';
import '../listen_sheet.dart';
import '../quote_card.dart';

// ======================= TYPE =======================

class TypeControls extends StatelessWidget {
  const TypeControls({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return ListenableBuilder(
      listenable: Settings.i,
      builder: (context, _) {
        final s = Settings.i;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            ToolButton(Icons.text_decrease_sharp, onTap: () => s.fontSize = s.fontSize - 1),
            Expanded(
              child: Column(children: [
                Text(s.fontSize.toStringAsFixed(0), style: mono(context, size: 26, color: t.ink, weight: FontWeight.w600, spacing: 0)),
                const Label('pt', size: 9),
              ]),
            ),
            ToolButton(Icons.text_increase_sharp, onTap: () => s.fontSize = s.fontSize + 1),
          ]),
          const SizedBox(height: 14),
          SizedBox(
            height: 64,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (final f in readerFonts)
                GestureDetector(
                  onTap: () {
                    haptic();
                    s.fontFamily = f;
                  },
                  child: Container(
                    width: 86,
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: s.fontFamily == f ? t.ink : t.raised,
                      borderRadius: t.br,
                      border: Border.all(color: s.fontFamily == f ? t.ink : t.line),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text('Aa', style: GoogleFonts.getFont(f, fontSize: 20, color: s.fontFamily == f ? t.bg : t.ink)),
                      Text(f, maxLines: 1, overflow: TextOverflow.ellipsis, style: mono(context, size: 8.5, color: s.fontFamily == f ? t.bg : t.muted, spacing: 0)),
                    ]),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 10),
          SliderRow(label: 'Leading', value: s.lineHeight, min: 1.1, max: 2.4, divisions: 26, format: (v) => v.toStringAsFixed(2), onChanged: (v) => s.lineHeight = v),
          SliderRow(label: 'Para gap', value: s.paragraphSpacing, min: 0, max: 2.5, divisions: 25, format: (v) => v.toStringAsFixed(1), onChanged: (v) => s.paragraphSpacing = v),
          SliderRow(label: 'Tracking', value: s.letterSpacing, min: -1, max: 3, divisions: 40, format: (v) => v.toStringAsFixed(1), onChanged: (v) => s.letterSpacing = v),
          SliderRow(label: 'Weight', value: s.fontWeight.toDouble(), min: 300, max: 700, divisions: 4, format: (v) => v.round().toString(), onChanged: (v) => s.fontWeight = v.round()),
          SliderRow(label: 'Margins', value: s.margin, min: 8, max: 72, divisions: 32, format: (v) => v.round().toString(), onChanged: (v) => s.margin = v),
          const SizedBox(height: 6),
          Segmented<bool>(values: const [false, true], labels: const ['Ragged', 'Justified'], value: s.justify, onChanged: (v) => s.justify = v),
          const SizedBox(height: 6),
          ToggleRow(label: 'Indent paragraphs', value: s.indentParagraphs, onChanged: (v) => s.indentParagraphs = v),
          ToggleRow(label: 'Show images', value: s.showImages, onChanged: (v) => s.showImages = v),
          Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => s.reset(Settings.readerKeys), child: Label('Reset type', color: t.accent))),
        ]);
      },
    );
  }
}

// ======================= LIGHT =======================

class LightControls extends StatefulWidget {
  const LightControls({super.key});

  @override
  State<LightControls> createState() => _LightControlsState();
}

class _LightControlsState extends State<LightControls> {
  double? _b;

  @override
  void initState() {
    super.initState();
    ScreenBrightness.instance.application.then((v) => mounted ? setState(() => _b = v) : null).catchError((_) => 0.5);
  }

  Widget _surfaceTile(BuildContext context, Surface sf, bool selected, VoidCallback onTap) {
    final t = Tokens.of(context);
    return GestureDetector(
      onTap: () {
        haptic();
        onTap();
      },
      child: Container(
        width: 62,
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: sf.bg, borderRadius: t.br, border: Border.all(color: selected ? t.accent : t.line, width: selected ? 2 : 1)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Aa', style: TextStyle(color: sf.fg, fontWeight: FontWeight.w700, fontSize: 16)),
          Text(sf.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: monoFont(color: sf.fg.withValues(alpha: .7), fontSize: 8)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return ListenableBuilder(
      listenable: Settings.i,
      builder: (context, _) {
        final s = Settings.i;
        final custom = Surface('custom', 'Custom', s.customBg, s.customFg);
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SliderRow(
            label: 'Brightness',
            icon: Icons.light_mode_outlined,
            value: _b ?? .5,
            min: 0,
            max: 1,
            format: (v) => '${(v * 100).round()}',
            onChanged: (v) {
              setState(() => _b = v);
              ScreenBrightness.instance.setApplicationScreenBrightness(v);
            },
          ),
          SliderRow(label: 'Super dim', icon: Icons.dark_mode_outlined, value: s.dim, min: 0, max: .8, format: (v) => '${(v * 100).round()}', onChanged: (v) => s.dim = v),
          SliderRow(label: 'Warmth', icon: Icons.wb_twilight_outlined, value: s.warmth, min: 0, max: .6, format: (v) => '${(v * 100).round()}', onChanged: (v) => s.warmth = v),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () {
                ScreenBrightness.instance.resetApplicationScreenBrightness();
                ScreenBrightness.instance.application.then((v) => setState(() => _b = v));
              },
              child: Label('Use system brightness', color: t.accent),
            ),
          ),
          const SizedBox(height: 6),
          ToggleRow(label: 'Night mode', value: s.night, onChanged: (v) => s.night = v),
          ToggleRow(label: 'Follow system dark mode', value: s.nightFollowsSystem, onChanged: (v) => s.nightFollowsSystem = v),
          const SizedBox(height: 10),
          const Label('Day surface'),
          const SizedBox(height: 8),
          SizedBox(
            height: 62,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (final sf in surfaces.where((x) => !x.dark)) _surfaceTile(context, sf, s.daySurface == sf.id, () => s.daySurface = sf.id),
              _surfaceTile(context, custom, s.daySurface == 'custom', () => s.daySurface = 'custom'),
            ]),
          ),
          const SizedBox(height: 12),
          const Label('Night surface'),
          const SizedBox(height: 8),
          SizedBox(
            height: 62,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (final sf in surfaces.where((x) => x.dark)) _surfaceTile(context, sf, s.nightSurface == sf.id, () => s.nightSurface = sf.id),
              _surfaceTile(context, custom, s.nightSurface == 'custom', () => s.nightSurface = 'custom'),
            ]),
          ),
          const SizedBox(height: 14),
          const Label('Custom surface'),
          ColorRow(label: 'Page colour', color: s.customBg, onChanged: (c) => s.customBg = c),
          ColorRow(label: 'Ink colour', color: s.customFg, onChanged: (c) => s.customFg = c),
        ]);
      },
    );
  }
}

// ======================= MOTION =======================

class MotionControls extends StatelessWidget {
  const MotionControls({super.key, this.showListen = true});

  /// Off where read-aloud has its own page.
  final bool showListen;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Settings.i,
      builder: (context, _) {
        final s = Settings.i;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Label('Auto-scroll'),
          SliderRow(label: 'Speed', value: s.autoScrollSpeed, min: 5, max: 300, format: (v) => '${v.round()}px', onChanged: (v) => s.autoScrollSpeed = v),
          ToggleRow(label: 'Pause while touching', value: s.autoScrollPauseOnTouch, onChanged: (v) => s.autoScrollPauseOnTouch = v),
          const SizedBox(height: 10),
          const Label('Swipe mode'),
          const SizedBox(height: 8),
          const SwipeControls(compact: true),
          SliderRow(label: 'Auto WPM', value: s.swipeWpm.toDouble(), min: 100, max: 600, divisions: 50, format: (v) => '${v.round()}', onChanged: (v) => s.swipeWpm = v.round()),
          ToggleRow(label: 'Auto-advance cards', value: s.swipeAuto, onChanged: (v) => s.swipeAuto = v),
          ToggleRow(label: 'Swipe sideways', hint: 'Horizontal instead of vertical', value: s.swipeHorizontal, onChanged: (v) => s.swipeHorizontal = v),
          const SizedBox(height: 10),
          const Label('Gestures'),
          const SizedBox(height: 8),
          Row(children: [const SizedBox(width: 96, child: Label('Brightness')), Expanded(child: _EdgePicker(value: s.brightnessEdge, onChanged: (v) => s.brightnessEdge = v))]),
          const SizedBox(height: 8),
          Row(children: [const SizedBox(width: 96, child: Label('Font size')), Expanded(child: _EdgePicker(value: s.fontSizeEdge, onChanged: (v) => s.fontSizeEdge = v))]),
          ToggleRow(label: 'Tap zones', hint: 'Tap top/bottom to page, centre for controls', value: s.tapZones, onChanged: (v) => s.tapZones = v),
          ToggleRow(label: 'Volume keys turn pages', hint: 'They change the volume while audio plays.', value: s.volumePaging, onChanged: (v) => s.volumePaging = v),
          if (s.volumePaging) ...[
            const SizedBox(height: 4),
            const Label('Next page'),
            const SizedBox(height: 8),
            Segmented<bool>(values: const [false, true], labels: const ['Volume down', 'Volume up'], value: s.volumePagingSwapped, onChanged: (v) => s.volumePagingSwapped = v),
            const SizedBox(height: 8),
          ],
          ToggleRow(label: 'Keep screen awake', value: s.keepAwake, onChanged: (v) => s.keepAwake = v),
          ToggleRow(label: 'Immersive (hide system bars)', value: s.immersive, onChanged: (v) => s.immersive = v),
          ToggleRow(label: 'Status line', hint: 'Chapter, progress and clock while reading', value: s.showReaderHud, onChanged: (v) => s.showReaderHud = v),
          ToggleRow(label: 'Clock in status line', value: s.showClock, onChanged: (v) => s.showClock = v),
          if (showListen) ...[
          const SizedBox(height: 10),
          const Label('Listen'),
          const SizedBox(height: 8),
          Panel(
            onTap: () => showListenSheet(context, play: false),
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              const Label('Voice'),
              const Spacer(),
              Flexible(child: Text(Speech.summary, maxLines: 1, overflow: TextOverflow.ellipsis, style: mono(context, size: 11, color: Tokens.of(context).ink, spacing: 0))),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right_sharp, color: Tokens.of(context).muted),
            ]),
          ),
          SliderRow(label: 'Voice rate', value: s.ttsRate, min: .2, max: 1, format: (v) => v.toStringAsFixed(2), onChanged: (v) => s.ttsRate = v),
          SliderRow(label: 'Pitch', value: s.ttsPitch, min: .5, max: 2, format: (v) => v.toStringAsFixed(2), onChanged: (v) => s.ttsPitch = v),
          ],
        ]);
      },
    );
  }
}

/// Card size for swipe mode: fill the screen, or a fixed number of words.
class SwipeControls extends StatelessWidget {
  const SwipeControls({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return ListenableBuilder(
      listenable: Settings.i,
      builder: (context, _) {
        final s = Settings.i;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (!compact) ...[
            Label('Card size', color: t.accent),
            const SizedBox(height: 12),
          ],
          Segmented<bool>(values: const [true, false], labels: const ['Fit to screen', 'Fixed words'], value: s.swipeFit, onChanged: (v) => s.swipeFit = v),
          const SizedBox(height: 6),
          if (s.swipeFit)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text('Each card holds as much as fits on screen at your text size.', style: TextStyle(color: t.muted, fontSize: 12.5)),
            )
          else ...[
            SliderRow(label: 'Words/card', value: s.swipeWords.toDouble(), min: 30, max: 400, divisions: 37, format: (v) => '${v.round()}', onChanged: (v) => s.swipeWords = v.round()),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final (n, l) in const [(60, 'Short'), (120, 'Medium'), (200, 'Long'), (320, 'Page')]) Tag('$l · $n', filled: s.swipeWords == n, onTap: () => s.swipeWords = n),
            ]),
            const SizedBox(height: 4),
          ],
          SliderRow(label: 'Text scale', value: s.swipeFontScale, min: .8, max: 1.8, divisions: 20, format: (v) => '${v.toStringAsFixed(2)}×', onChanged: (v) => s.swipeFontScale = v),
        ]);
      },
    );
  }
}

class _EdgePicker extends StatelessWidget {
  const _EdgePicker({required this.value, required this.onChanged});
  final EdgeSide value;
  final ValueChanged<EdgeSide> onChanged;

  @override
  Widget build(BuildContext context) =>
      Segmented<EdgeSide>(values: EdgeSide.values, labels: const ['Left', 'Right', 'Both', 'Off'], value: value, onChanged: onChanged);
}

// ======================= NAVIGATOR (TOC / MARKS / NOTES / FIND) =======================

Future<void> showNavigator(BuildContext context, {required Book book, required ParsedDoc doc, required int current, required void Function(int block, {String? search}) onJump, int tab = 0, String? query}) {
  return showSheet(context, scroll: false, maxHeight: .9, builder: (ctx) => _Navigator(book: book, doc: doc, current: current, onJump: onJump, tab: tab, query: query));
}

class _Navigator extends StatefulWidget {
  const _Navigator({required this.book, required this.doc, required this.current, required this.onJump, this.tab = 0, this.query});
  final Book book;
  final ParsedDoc doc;
  final int current;
  final void Function(int block, {String? search}) onJump;
  final int tab;
  final String? query;

  @override
  State<_Navigator> createState() => _NavigatorState();
}

class _NavigatorState extends State<_Navigator> with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 4, vsync: this, initialIndex: widget.tab);
  late final _q = TextEditingController(text: widget.query ?? '');
  List<(int, String, int)> _results = [];

  @override
  void initState() {
    super.initState();
    if ((widget.query ?? '').isNotEmpty) _search(widget.query!);
  }

  void _search(String q) {
    final out = <(int, String, int)>[];
    if (q.trim().length >= 2) {
      final needle = q.toLowerCase();
      for (var i = 0; i < widget.doc.blocks.length && out.length < 300; i++) {
        final text = widget.doc.blocks[i].text;
        final at = text.toLowerCase().indexOf(needle);
        if (at >= 0) out.add((i, text, at));
      }
    }
    setState(() => _results = out);
  }

  void _go(int block, {String? search}) {
    Navigator.pop(context);
    widget.onJump(block, search: search);
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Column(children: [
      TabBar(
        controller: _tabs,
        indicatorColor: t.accent,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: t.line,
        labelColor: t.ink,
        unselectedLabelColor: t.muted,
        labelStyle: mono(context, size: 10.5, weight: FontWeight.w700),
        tabs: const [Tab(text: 'CONTENTS'), Tab(text: 'MARKS'), Tab(text: 'NOTES'), Tab(text: 'FIND')],
      ),
      Expanded(
        child: ListenableBuilder(
          listenable: Library.i,
          builder: (context, _) => TabBarView(controller: _tabs, children: [_toc(context), _marks(context), _notes(context), _find(context)]),
        ),
      ),
    ]);
  }

  Widget _toc(BuildContext context) {
    final t = Tokens.of(context);
    final toc = widget.doc.toc;
    if (toc.isEmpty) return const Center(child: Label('No chapters in this file'));
    final cur = widget.doc.chapterAt(widget.current);
    final total = widget.doc.wordCount == 0 ? 1 : widget.doc.wordCount;
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: toc.length,
      itemBuilder: (_, i) {
        final e = toc[i];
        final active = identical(e, cur);
        final pct = (widget.doc.wordOffsets[e.block.clamp(0, widget.doc.blocks.length)] / total * 100).round();
        return InkWell(
          onTap: () => _go(e.block),
          child: Container(
            padding: EdgeInsets.fromLTRB(20 + e.depth * 16.0, 12, 20, 12),
            decoration: BoxDecoration(border: Border(left: BorderSide(color: active ? t.accent : Colors.transparent, width: 3))),
            child: Row(children: [
              SizedBox(width: 30, child: Label(pad(i + 1), color: active ? t.accent : t.muted)),
              Expanded(child: Text(e.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.ink, fontWeight: active ? FontWeight.w700 : (e.depth == 0 ? FontWeight.w500 : FontWeight.w400)))),
              Label('$pct%'),
            ]),
          ),
        );
      },
    );
  }

  Widget _marks(BuildContext context) {
    final t = Tokens.of(context);
    final marks = Library.i.bookmarksFor(widget.book.id);
    if (marks.isEmpty) return const Center(child: Label('Tap the bookmark icon while reading'));
    return ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: [
      for (final m in marks)
        InkWell(
          onTap: () => _go(m.block),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(padding: const EdgeInsets.only(top: 2), child: Icon(Icons.bookmark_sharp, size: 18, color: t.accent)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(m.label, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.ink, fontWeight: FontWeight.w600)),
                  if (m.excerpt.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('“${m.excerpt}”', maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.muted, fontStyle: FontStyle.italic, height: 1.4))),
                  const SizedBox(height: 4),
                  Label('${(m.progress * 100).toStringAsFixed(1)}%  ·  ${pad(m.createdAt.day)}.${pad(m.createdAt.month)}.${m.createdAt.year}', size: 9),
                ]),
              ),
              IconButton(
                tooltip: 'Share card',
                icon: Icon(Icons.ios_share_sharp, size: 18, color: t.muted),
                onPressed: () => shareBookmark(context, widget.book, m, passage: widget.doc.blocks.isEmpty ? null : widget.doc.blocks[m.block.clamp(0, widget.doc.blocks.length - 1)].text),
              ),
              PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'rename') {
                    final n = await promptText(context, title: 'Rename bookmark', initial: m.label);
                    if (n != null) Library.i.renameBookmark(m, n);
                  } else {
                    Library.i.removeBookmark(m);
                  }
                },
                itemBuilder: (_) => const [PopupMenuItem(value: 'rename', child: Text('Rename')), PopupMenuItem(value: 'delete', child: Text('Delete'))],
              ),
            ]),
          ),
        ),
    ]);
  }

  Widget _notes(BuildContext context) {
    final t = Tokens.of(context);
    final hls = Library.i.highlightsFor(widget.book.id);
    if (hls.isEmpty) return const Center(child: Label('Select text to highlight'));
    return ListView(padding: const EdgeInsets.all(16), children: [
      for (final h in hls)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GestureDetector(
            onTap: () => _go(h.block),
            onLongPress: () => editHighlight(context, widget.book, h),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: t.raised, borderRadius: t.br, border: t.hair),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(width: 3, height: 36, color: highlightColor(h.color)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(h.text, maxLines: 4, overflow: TextOverflow.ellipsis, style: const TextStyle(height: 1.4)),
                    if (h.note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text('— ${h.note}', style: TextStyle(color: t.muted, fontStyle: FontStyle.italic))),
                    const SizedBox(height: 6),
                    Label(widget.doc.chapterAt(h.block)?.title ?? '', size: 9),
                  ]),
                ),
                Column(children: [
                  IconButton(icon: Icon(Icons.ios_share_sharp, color: t.muted, size: 18), onPressed: () => shareHighlight(context, widget.book, h, chapter: widget.doc.chapterAt(h.block)?.title)),
                  IconButton(icon: Icon(Icons.more_horiz_sharp, color: t.muted, size: 18), onPressed: () => editHighlight(context, widget.book, h)),
                ]),
              ]),
            ),
          ),
        ),
    ]);
  }

  Widget _find(BuildContext context) {
    final t = Tokens.of(context);
    final q = _q.text.toLowerCase();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: SearchBox(historyKey: 'find-in-book', 
          controller: _q,
          autofocus: widget.tab == 3 && (widget.query ?? '').isEmpty,
          decoration: const InputDecoration(hintText: 'Search in book', prefixIcon: Icon(Icons.search_sharp, size: 18)),
          onChanged: _search,
        ),
      ),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Align(alignment: Alignment.centerLeft, child: Label('${_results.length}${_results.length >= 300 ? '+' : ''} results'))),
      Expanded(
        child: ListView.builder(
          itemCount: _results.length,
          itemBuilder: (_, i) {
            final (block, text, at) = _results[i];
            final from = (at - 50).clamp(0, text.length);
            final to = (at + q.length + 70).clamp(0, text.length);
            return InkWell(
              onTap: () => _go(block, search: _q.text),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Label(widget.doc.chapterAt(block)?.title ?? 'Block $block', size: 9, color: t.accent),
                  const SizedBox(height: 4),
                  Text.rich(TextSpan(style: TextStyle(color: t.ink, height: 1.4), children: [
                    TextSpan(text: '${from > 0 ? '…' : ''}${text.substring(from, at)}'),
                    TextSpan(text: text.substring(at, (at + q.length).clamp(0, text.length)), style: TextStyle(backgroundColor: t.accent.withValues(alpha: .35), fontWeight: FontWeight.w700)),
                    TextSpan(text: '${text.substring((at + q.length).clamp(0, text.length), to)}${to < text.length ? '…' : ''}'),
                  ])),
                ]),
              ),
            );
          },
        ),
      ),
    ]);
  }
}

// ======================= HIGHLIGHT EDIT =======================

Future<void> editHighlight(BuildContext context, Book book, Highlight h) {
  final note = TextEditingController(text: h.note);
  return showSheet(context, builder: (ctx) {
    final t = Tokens.of(ctx);
    return StatefulBuilder(builder: (ctx, setS) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.only(left: 12),
            decoration: BoxDecoration(border: Border(left: BorderSide(color: highlightColor(h.color), width: 3))),
            child: Text(h.text, maxLines: 6, overflow: TextOverflow.ellipsis, style: const TextStyle(height: 1.45)),
          ),
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (var i = 0; i < highlightColors.length; i++)
              GestureDetector(
                onTap: () {
                  haptic();
                  h.color = i;
                  Library.i.updateHighlight(h);
                  setS(() {});
                },
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: highlightColors[i], borderRadius: t.br, border: Border.all(color: h.color == i ? t.ink : Colors.transparent, width: 2)),
                ),
              ),
          ]),
          const SizedBox(height: 14),
          TextField(controller: note, maxLines: 3, decoration: const InputDecoration(hintText: 'Add a note…')),
          const SizedBox(height: 14),
          Row(children: [
            ToolButton(Icons.delete_outline_sharp, onTap: () {
              Library.i.removeHighlight(h);
              Navigator.pop(ctx);
            }),
            const SizedBox(width: 8),
            ToolButton(Icons.ios_share_sharp, label: 'Card', onTap: () {
              Navigator.pop(ctx);
              shareHighlight(context, book, h);
            }),
            const SizedBox(width: 8),
            ToolButton(Icons.bookmark_add_outlined, tooltip: 'Bookmark this passage', onTap: () {
              Library.i.addBookmark(book.id, h.block, h.text.length > 40 ? '${h.text.substring(0, 40)}…' : h.text, book.progress, excerpt: h.text);
              toast(ctx, 'Bookmarked');
            }),
            const Spacer(),
            PrimaryButton('Save', onTap: () {
              h.note = note.text.trim();
              Library.i.updateHighlight(h);
              Navigator.pop(ctx);
            }),
          ]),
        ]),
      );
    });
  });
}

// ======================= DICTIONARY =======================

Future<void> showDefine(BuildContext context, String word, {VoidCallback? onAskAi}) {
  return showSheet(context, builder: (ctx) {
    final t = Tokens.of(ctx);
    return FutureBuilder<DictEntry>(
      future: Dictionary.lookup(word),
      builder: (ctx, snap) {
        final e = snap.data;
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Label('Dictionary', color: t.accent),
              const Spacer(),
              GestureDetector(onTap: () => DeviceSpeech.instance.speak(word, rate: Speech.rate), child: Icon(Icons.volume_up_outlined, size: 20, color: t.ink)),
            ]),
            const SizedBox(height: 6),
            Text(word, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: -.8)),
            if (e != null && e.phonetic.isNotEmpty) Text(e.phonetic, style: mono(ctx, size: 13, spacing: 0)),
            const SizedBox(height: 14),
            if (snap.connectionState != ConnectionState.done)
              const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator(strokeWidth: 1.5)))
            else if (e == null || e.isEmpty)
              Text('No dictionary entry found. Try AI for an in-context meaning.', style: TextStyle(color: t.muted))
            else ...[
              for (final (source, defs) in [
                for (final src in e.definitions.map((d) => d.source).toSet()) (src, e.definitions.where((d) => d.source == src).take(6).toList()),
              ]) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 10, top: 2),
                  child: Row(children: [
                    Label(source, color: t.ink, weight: FontWeight.w600),
                    const SizedBox(width: 8),
                    Expanded(child: Container(height: 1, color: t.line)),
                  ]),
                ),
                for (final d in defs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(width: 56, child: Label(d.partOfSpeech.length > 6 ? d.partOfSpeech.substring(0, 6) : d.partOfSpeech, color: t.accent)),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(d.text, style: const TextStyle(height: 1.4)),
                        if (d.example != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text('“${d.example}”', style: TextStyle(color: t.muted, fontStyle: FontStyle.italic))),
                        if (d.synonyms.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Label('≈ ${d.synonyms.join(', ')}', size: 9.5)),
                      ]),
                    ),
                  ]),
                ),
              ],
              if (e.wiki != null) ...[
                const SizedBox(height: 6),
                Panel(
                  padding: const EdgeInsets.all(12),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (e.wikiImage != null) Padding(padding: const EdgeInsets.only(right: 12), child: NetImage(e.wikiImage!, width: 56, height: 56)),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Label('Wikipedia'),
                        const SizedBox(height: 4),
                        Text(e.wiki!, maxLines: 6, overflow: TextOverflow.ellipsis, style: const TextStyle(height: 1.4, fontSize: 13.5)),
                      ]),
                    ),
                  ]),
                ),
              ],
            ],
            const SizedBox(height: 14),
            if (onAskAi != null)
              PrimaryButton('Explain in context with AI', icon: Icons.auto_awesome_outlined, expand: true, onTap: () {
                Navigator.pop(ctx);
                onAskAi();
              }),
          ]),
        );
      },
    );
  });
}
