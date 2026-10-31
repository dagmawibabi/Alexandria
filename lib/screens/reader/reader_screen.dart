import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:super_sliver_list/super_sliver_list.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/settings.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../models/annotations.dart';
import '../../models/audiobook.dart';
import '../../models/book.dart';
import '../../models/doc.dart';
import '../../services/ai.dart';
import '../../services/audio.dart';
import '../../services/library.dart';
import '../../services/read_aloud.dart';
import '../../services/speech.dart';
import '../../services/volume_keys.dart';
import '../ai_sheets.dart';
import '../listen_sheet.dart';
import '../quote_card.dart';
import 'block_view.dart';
import 'reader_sheets.dart';
import 'swipe_view.dart';

enum ReadMode { scroll, swipe, pdf }

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key, required this.book, this.follow});
  final Book book;

  /// An audiobook narrating this book: the page follows its playback.
  final Audiobook? follow;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> with WidgetsBindingObserver, SingleTickerProviderStateMixin, RouteAware {
  Book get book => widget.book;
  ParsedDoc? _doc;
  Object? _error;

  final _scroll = ScrollController();
  final _list = ListController();
  PdfViewerController? _pdf;
  ReadMode _mode = ReadMode.scroll;
  int _current = 0;
  bool _hud = true;
  String? _search;

  // auto-scroll
  late final Ticker _ticker = createTicker(_tick);
  bool _auto = false;
  bool _touching = false;
  Duration _lastTick = Duration.zero;

  // gestures / overlays
  double _brightness = .5;
  String? _overlay;
  double? _overlayValue;
  Timer? _overlayTimer;

  // listen
  /// The paragraph being read aloud, if it's this book.
  int? get _speakingBlock => ReadAloud.i.isOn(book) ? ReadAloud.i.block : null;
  int? _lastSpoken;

  // position slider: the fraction being dragged to, before it is applied
  double? _drag;
  DateTime _lastScrub = DateTime(0);

  /// How far through [_current] the top of the screen is (0..1), measured from layout.
  double _inner = 0;

  /// Laid-out blocks by index, so the reading position can be measured on screen.
  final Map<int, BuildContext> _items = {};

  // session
  late DateTime _sessionStart;
  int _activeSecs = 0;
  late int _startWords;
  DateTime _lastInteract = DateTime.now();
  Timer? _clock;
  Timer? _saveTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.follow != null) Player.i.addListener(_onAudio);
    ReadAloud.i.addListener(_onReadAloud);
    for (final l in [Settings.i, Player.i, ReadAloud.i]) {
      l.addListener(_syncVolumeKeys);
    }
    _current = book.position;
    _inner = book.positionOffset.clamp(0.0, 1.0);
    book.lastOpenedAt = DateTime.now();
    if (book.status == ReadStatus.unread) book.status = ReadStatus.reading;
    Library.i.touch(book);
    _scroll.addListener(_onScroll);
    _load();
    _beginSession();
    if (Settings.i.keepAwake) WakelockPlus.enable();
    ScreenBrightness.instance.application.then((v) => _brightness = v).catchError((_) => .5);
    Future.delayed(const Duration(milliseconds: 2200), () {
      if (mounted && _hud && !_anySheet) _setHud(false);
    });
  }

  bool _anySheet = false;

  Future<void> _load() async {
    try {
      final doc = await Library.i.doc(book);
      if (!mounted) return;
      setState(() {
        _doc = doc;
        // A scanned PDF has no blocks: its place is a page, and stays as it is.
        if (doc.blocks.isNotEmpty) _current = _current.clamp(0, doc.blocks.length - 1);
        _startWords = _wordsBefore(doc, _current);
        if (book.format == BookFormat.pdf && (Settings.i.pdfOriginal || doc.wordCount < 50)) _mode = ReadMode.pdf;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpTo(_current, inner: _inner));
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _beginSession() {
    _sessionStart = DateTime.now();
    _activeSecs = 0;
    final d = _doc;
    _startWords = d == null ? 0 : _wordsBefore(d, _current);
    _clock?.cancel();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      final idle = DateTime.now().difference(_lastInteract).inSeconds;
      if ((idle < 150 || _auto) && _speakingBlock == null) _activeSecs++;
      if (Settings.i.showClock && !_hud && mounted && DateTime.now().second == 0) setState(() {});
    });
  }

  void _endSession() {
    _clock?.cancel();
    final doc = _doc;
    if (doc == null) return;
    final words = math.max(0, _wordsBefore(doc, _current) - _startWords);
    Library.i.addSession(ReadingSession(
      bookId: book.id,
      start: _sessionStart,
      seconds: _activeSecs,
      words: words,
      mode: _mode.name,
    ));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      if (_clock?.isActive ?? false) {
        _savePosition(force: true);
        _endSession();
      }
    } else if (state == AppLifecycleState.resumed && !(_clock?.isActive ?? false)) {
      _beginSession();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    Player.i.removeListener(_onAudio);
    ReadAloud.i.removeListener(_onReadAloud);
    for (final l in [Settings.i, Player.i, ReadAloud.i]) {
      l.removeListener(_syncVolumeKeys);
    }
    VolumeKeys.routes.unsubscribe(this);
    _releaseVolumeKeys();
    _swipeTurns.close();
    _savePosition(force: true);
    _endSession();
    _ticker.dispose();
    // Read-aloud carries on after the reader closes; a one-off passage doesn't.
    if (!ReadAloud.i.active) Speech.stop();
    _overlayTimer?.cancel();
    _saveTimer?.cancel();
    _scroll.dispose();
    WakelockPlus.disable();
    ScreenBrightness.instance.resetApplicationScreenBrightness().catchError((_) {});
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ------------------------------------------------------------ volume keys

  final _swipeTurns = StreamController<int>.broadcast();

  /// Something is open on top of this reader.
  bool _covered = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) VolumeKeys.routes.subscribe(this, route);
  }

  @override
  void didPush() => _syncVolumeKeys();

  @override
  void didPushNext() {
    _covered = true;
    _syncVolumeKeys();
  }

  @override
  void didPopNext() {
    _covered = false;
    _syncVolumeKeys();
  }

  void _syncVolumeKeys() {
    if (VolumeKeys.wanted(enabled: Settings.i.volumePaging, covered: _covered, audioPlaying: Player.i.playing || ReadAloud.i.active)) {
      VolumeKeys.onTurn = _volumeTurn;
      VolumeKeys.capture(true);
    } else {
      _releaseVolumeKeys();
    }
  }

  /// Leaves them alone if another reader has already taken over.
  void _releaseVolumeKeys() {
    if (VolumeKeys.onTurn != _volumeTurn) return;
    VolumeKeys.onTurn = null;
    VolumeKeys.capture(false);
  }

  void _volumeTurn(int key) {
    final dir = Settings.i.volumePagingSwapped ? -key : key;
    _lastInteract = DateTime.now();
    switch (_mode) {
      case ReadMode.scroll:
        if (_scroll.hasClients) _page(dir);
      case ReadMode.swipe:
        _swipeTurns.add(dir);
      case ReadMode.pdf:
        final pdf = _pdf;
        if (pdf == null || !pdf.isReady) return;
        final to = (pdf.pageNumber ?? 1) + dir;
        if (to >= 1 && to <= pdf.pageCount) pdf.goToPage(pageNumber: to);
        haptic();
    }
  }

  // ------------------------------------------------------------ position

  double get _progress => _fractionOf(_current, _mode == ReadMode.scroll ? _inner : 0);

  /// Words before [block]. In a scanned PDF [block] is a page and there are no words.
  int _wordsBefore(ParsedDoc d, int block) => d.wordOffsets[block.clamp(0, d.blocks.length)];

  double _fractionOf(int block, [double inner = 0]) {
    final d = _doc;
    if (d == null) return book.progress;
    if (d.blocks.isEmpty) return d.pageCount > 1 ? (block / (d.pageCount - 1)).clamp(0.0, 1.0) : book.progress;
    if (d.wordCount == 0) return (block + inner) / d.blocks.length;
    return (d.wordOffsets[block] + inner * d.blocks[block].words) / d.wordCount;
  }

  /// Where on screen the reading position is read from: just under the status bar.
  double get _readLine => MediaQuery.of(context).padding.top + 16;

  /// The block holding word [f] × total: the inverse of [_fractionOf], so the
  /// position slider moves by reading distance rather than by block count.
  int _blockAt(double f) {
    final d = _doc;
    if (d == null || d.blocks.isEmpty) return 0;
    if (d.wordCount == 0) return (f * (d.blocks.length - 1)).round();
    final target = f.clamp(0.0, 1.0) * d.wordCount;
    var lo = 0, hi = d.blocks.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (d.wordOffsets[mid] <= target) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  /// Finds the block under [_readLine] and how far through it the line sits.
  (int, double)? _measure() {
    final d = _doc;
    if (d == null || d.blocks.isEmpty || !_scroll.hasClients) return null;
    final pos = _scroll.position;
    if (pos.maxScrollExtent > 0 && pos.pixels >= pos.maxScrollExtent - 1) return (d.blocks.length - 1, 1.0);
    final line = _readLine;
    (int, double)? below;
    for (final e in _items.entries) {
      final box = e.value.mounted ? e.value.findRenderObject() : null;
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      final top = box.localToGlobal(Offset.zero).dy;
      final h = box.size.height;
      if (top <= line && line < top + h) return (e.key, h <= 0 ? 0.0 : ((line - top) / h).clamp(0.0, 1.0));
      // The line falls in a gap (top padding, an empty block): use the next block's start.
      if (top > line && (below == null || e.key < below.$1)) below = (e.key, 0.0);
    }
    return below;
  }

  void _onScroll() {
    if (_mode != ReadMode.scroll) return;
    final m = _measure();
    if (m == null) return;
    final changed = m.$1 != _current || (m.$2 - _inner).abs() > .002;
    _current = m.$1;
    _inner = m.$2;
    if (changed) {
      _savePosition();
      setState(() {});
    }
  }

  /// Scrolls so the reading line sits [inner] of the way through [block].
  void _jumpTo(int block, {double inner = 0}) {
    final d = _doc;
    if (d == null || !_list.isAttached || !_scroll.hasClients) return;
    block = block.clamp(0, math.max(0, d.blocks.length - 1));
    final view = _scroll.position.viewportDimension;
    _list.jumpToItem(index: block, scrollController: _scroll, alignment: view > 0 ? (_readLine / view).clamp(0.0, .5) : 0);
    _current = block;
    _inner = inner;
    // Once the block is laid out, nudge by the part of it already read.
    void settle(int tries) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        final box = _items[block]?.findRenderObject();
        if (box is! RenderBox || !box.attached || !box.hasSize) {
          if (tries > 0) settle(tries - 1);
          return;
        }
        final top = box.localToGlobal(Offset.zero).dy;
        final target = _scroll.position.pixels + (top - _readLine) + inner * box.size.height;
        _scroll.jumpTo(target.clamp(0.0, _scroll.position.maxScrollExtent));
        _onScroll();
      });
    }

    settle(2);
  }

  /// Jumps to a fraction of the book by reading distance (the slider).
  void _jumpToFraction(double f) {
    final d = _doc;
    if (d == null || d.blocks.isEmpty) return;
    final block = _blockAt(f);
    final words = d.blocks[block].words;
    final inner = d.wordCount == 0 || words == 0 ? 0.0 : ((f * d.wordCount - d.wordOffsets[block]) / words).clamp(0.0, 1.0);
    if (_mode == ReadMode.scroll) {
      _jumpTo(block, inner: inner);
      setState(() {});
      _savePosition();
    } else {
      _jump(block, animate: false);
    }
  }

  void _setCurrent(int block) {
    if (block != _current) _inner = 0;
    _current = block;
    _lastInteract = DateTime.now();
    _savePosition();
    setState(() {});
  }

  void _savePosition({bool force = false}) {
    void write() {
      book.position = _current;
      book.positionOffset = _mode == ReadMode.scroll ? _inner : 0;
      book.progress = _progress.clamp(0, 1);
      if (book.progress > .985 && book.status != ReadStatus.finished) {
        book.status = ReadStatus.finished;
        book.finishedAt = DateTime.now();
      }
      Library.i.touch(book);
    }

    if (force) {
      _saveTimer?.cancel();
      write();
      return;
    }
    if (_saveTimer?.isActive ?? false) return;
    _saveTimer = Timer(const Duration(seconds: 2), write);
  }

  void _jump(int block, {bool animate = true, String? search}) {
    final d = _doc;
    if (d == null) return;
    block = block.clamp(0, math.max(0, d.blocks.length - 1));
    setState(() {
      _search = search;
      _current = block;
      _inner = 0;
    });
    if (_mode == ReadMode.scroll && _list.isAttached && _scroll.hasClients) {
      if (animate) {
        final view = _scroll.position.viewportDimension;
        _list.animateToItem(
          index: block,
          scrollController: _scroll,
          alignment: view > 0 ? (_readLine / view).clamp(0.0, .5) : 0,
          duration: (d) => Duration(milliseconds: (220 + d / 12).clamp(220, 650).round()),
          curve: (_) => Curves.easeOutCubic,
        );
      } else {
        _jumpTo(block);
      }
    } else if (_mode == ReadMode.pdf) {
      final page = d.blocks.isEmpty ? 0 : (d.blocks[block].page ?? 0);
      _pdf?.goToPage(pageNumber: page + 1);
    } else if (_mode == ReadMode.swipe) {
      setState(() => _swipeKey = UniqueKey());
    }
    _savePosition();
  }

  Key _swipeKey = UniqueKey();

  // ------------------------------------------------------------ HUD

  void _setHud(bool v) {
    setState(() => _hud = v);
    if (Settings.i.immersive) {
      SystemChrome.setEnabledSystemUIMode(v ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky);
    }
  }

  Future<T?> _sheet<T>(Widget Function(BuildContext) builder, {String? title}) async {
    _anySheet = true;
    final t = await showSheet<T>(context, builder: (ctx) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (title != null) Padding(padding: const EdgeInsets.only(bottom: 14), child: Label(title, color: Tokens.of(ctx).accent)),
          builder(ctx),
        ]),
      );
    });
    _anySheet = false;
    return t;
  }

  void _flash(String label, double value) {
    _overlayTimer?.cancel();
    setState(() {
      _overlay = label;
      _overlayValue = value;
    });
    _overlayTimer = Timer(const Duration(milliseconds: 900), () => mounted ? setState(() => _overlay = null) : null);
  }

  // ------------------------------------------------------------ auto-scroll

  void _toggleAuto() {
    if (_mode != ReadMode.scroll) {
      setState(() => _mode = ReadMode.scroll);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _jumpTo(_current, inner: _inner);
        _toggleAuto();
      });
      return;
    }
    setState(() => _auto = !_auto);
    if (_auto) {
      _lastTick = Duration.zero;
      _ticker.start();
      _setHud(false);
    } else {
      _ticker.stop();
    }
  }

  void _tick(Duration elapsed) {
    final dt = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    if (!_scroll.hasClients || (_touching && Settings.i.autoScrollPauseOnTouch)) return;
    final pos = _scroll.position;
    final next = pos.pixels + Settings.i.autoScrollSpeed * dt;
    if (next >= pos.maxScrollExtent) {
      _scroll.jumpTo(pos.maxScrollExtent);
      setState(() => _auto = false);
      _ticker.stop();
      return;
    }
    _scroll.jumpTo(next);
  }

  // ------------------------------------------------------------ listen

  /// Tapping Listen opens the voice sheet; tapping it while reading aloud stops.
  Future<void> _toggleListen() async {
    if (_speakingBlock != null) return ReadAloud.i.stop();
    _anySheet = true;
    final go = await showListenSheet(context);
    _anySheet = false;
    final d = _doc;
    if (go && mounted && d != null) ReadAloud.i.start(book, d, _current);
  }

  /// Keeps the page on the paragraph being read.
  void _onReadAloud() {
    if (!mounted) return;
    final b = _speakingBlock;
    if (b != null && b != _lastSpoken) {
      if (_mode == ReadMode.scroll) {
        final r = _list.isAttached ? _list.visibleRange : null;
        if (r == null || b < r.$1 || b > r.$2 - 1) _jump(b);
      }
      _setCurrent(b);
    }
    _lastSpoken = b;
    if (ReadAloud.i.fellBack && _speakingBlock != null) {
      ReadAloud.i.fellBack = false;
      toast(context, 'Cloud voice failed, using device voice');
    }
    setState(() {});
  }

  Widget _readBar(BuildContext context) {
    final t = Tokens.of(context);
    final r = ReadAloud.i;
    Widget b(IconData i, VoidCallback f, {bool strong = false}) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            haptic();
            f();
          },
          child: Padding(padding: const EdgeInsets.all(11), child: Icon(i, size: strong ? 24 : 20, color: strong ? t.accent : t.ink)),
        );
    return Positioned(
      left: 0,
      right: 0,
      bottom: MediaQuery.of(context).padding.bottom + 158,
      child: Center(
        child: Container(
          decoration: BoxDecoration(
            color: t.surface.withValues(alpha: .97),
            borderRadius: BorderRadius.circular(t.zen ? 14 : t.radius + 6),
            border: t.hair,
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .15), blurRadius: 14, offset: const Offset(0, 4))],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            b(Icons.skip_previous_sharp, r.previous),
            b(r.playing ? Icons.pause_sharp : Icons.play_arrow_sharp, r.toggle, strong: true),
            b(Icons.skip_next_sharp, r.next),
            Container(width: 1, height: 22, color: t.line),
            b(Icons.stop_sharp, r.stop),
          ]),
        ),
      ),
    );
  }

  /// Reads a passage once (selection menu, swipe card), interrupting any read-aloud.
  Future<void> _sayOnce(String text) async {
    if (ReadAloud.i.active) await ReadAloud.i.stop();
    await Speech.stop();
    await Speech.say(text);
  }

  // ------------------------------------------------------------ selection

  String _contextAround(int block) {
    final d = _doc!;
    final from = math.max(0, block - 2);
    final to = math.min(d.blocks.length, block + 3);
    return [for (var i = from; i < to; i++) d.blocks[i].text].where((s) => s.isNotEmpty).join('\n');
  }

  Future<void> _onSelection(SelAction a, int block, int start, int end, String text, {int color = 0}) async {
    _lastInteract = DateTime.now();
    switch (a) {
      case SelAction.highlight:
        Library.i.addHighlight(Highlight(id: newId(), bookId: book.id, block: block, start: start, end: end, text: text, color: color));
        haptic();
      case SelAction.bookmark:
        Library.i.addBookmark(book.id, block, _doc?.chapterAt(block)?.title ?? book.title, _doc == null || _doc!.wordCount == 0 ? _progress : _doc!.wordOffsets[block] / _doc!.wordCount, excerpt: text);
        haptic(true);
        toast(context, 'Passage bookmarked');
      case SelAction.unmark:
        for (final h in Library.i.highlightsFor(book.id).where((h) => h.block == block && h.start < end && start < h.end).toList()) {
          Library.i.removeHighlight(h);
        }
      case SelAction.note:
        final note = await promptText(context, title: 'Note', hint: 'Your thought…');
        if (note != null) {
          Library.i.addHighlight(Highlight(id: newId(), bookId: book.id, block: block, start: start, end: end, text: text, note: note, color: 2));
        }
      case SelAction.explain:
        _explain(text, block, 'explain');
      case SelAction.define:
        _anySheet = true;
        await showDefine(context, text, onAskAi: () => _explain(text, block, 'define'));
        _anySheet = false;
      case SelAction.quote:
        final hl = Library.i.highlightsFor(book.id).where((h) => h.block == block && h.start < end && start < h.end).firstOrNull;
        showQuoteCard(context, book: book, text: text, kind: hl == null ? CardKind.excerpt : CardKind.highlight, color: hl?.color, note: hl?.note ?? '', chapter: _doc?.chapterAt(block)?.title);
      case SelAction.copy:
        await Clipboard.setData(ClipboardData(text: text));
        if (mounted) toast(context, 'Copied');
      case SelAction.find:
        _openNavigator(tab: 3, query: text);
      case SelAction.speak:
        _sayOnce(text);
    }
  }

  Future<void> _explain(String text, int block, String mode) async {
    if (!await ensureAi(context) || !mounted) return;
    final ctx = _contextAround(block);
    _anySheet = true;
    await showAiStream(
      context,
      title: 'Explain',
      subtitle: text,
      book: book,
      passage: ctx,
      initialMode: mode,
      modes: const [('explain', 'Explain'), ('simplify', 'Simplify'), ('context', 'In this book'), ('define', 'Define'), ('translate', 'Translate')],
      make: () => Ai.explain(book: book, selection: text, context: ctx),
      makeMode: (m) => Ai.explain(book: book, selection: text, context: ctx, mode: m),
    );
    _anySheet = false;
  }

  void _openNavigator({int tab = 0, String? query}) {
    final d = _doc;
    if (d == null) return;
    _anySheet = true;
    showNavigator(context, book: book, doc: d, current: _current, tab: tab, query: query, onJump: (b, {search}) {
      if (_mode == ReadMode.swipe) {
        _current = b;
        _swipeKey = UniqueKey();
      }
      _jump(b, search: search);
    }).then((_) => _anySheet = false);
  }

  void _toggleBookmark([int? block]) {
    final d = _doc;
    if (d == null) return;
    final b = block ?? _current;
    final label = d.chapterAt(b)?.title ?? (d.blocks.isEmpty ? 'Page' : d.blocks[b].text);
    final snippet = d.blocks.isEmpty ? '' : d.blocks[b].text;
    final text = snippet.isEmpty ? label : '${label.length > 40 ? label.substring(0, 40) : label} — ${snippet.length > 60 ? '${snippet.substring(0, 60)}…' : snippet}';
    final had = Library.i.bookmarkAt(book.id, b) != null;
    Library.i.toggleBookmark(book.id, b, text, _progress);
    haptic(true);
    toast(context, had ? 'Bookmark removed' : 'Bookmarked');
    setState(() {});
  }

  void _setMode(ReadMode m) {
    if (m == _mode) return;
    _ticker.stop();
    _auto = false;
    if (m == ReadMode.pdf) Settings.i.pdfOriginal = true;
    if (_mode == ReadMode.pdf && m == ReadMode.scroll) Settings.i.pdfOriginal = false;
    setState(() {
      _mode = m;
      _swipeKey = UniqueKey();
    });
    if (m == ReadMode.scroll) WidgetsBinding.instance.addPostFrameCallback((_) => _jumpTo(_current, inner: _inner));
  }

  // ------------------------------------------------------------ edge gestures

  void _edgeDrag(DragUpdateDetails d, bool brightness) {
    _lastInteract = DateTime.now();
    final h = MediaQuery.of(context).size.height;
    if (brightness) {
      final s = Settings.i;
      final delta = -d.delta.dy / (h * .55);
      if (delta < 0 && _brightness <= 0.001) {
        s.dim = (s.dim - delta).clamp(0, .8);
        _flash('DIM', -s.dim);
      } else if (delta > 0 && s.dim > 0) {
        s.dim = (s.dim - delta).clamp(0, .8);
        _flash('DIM', -s.dim);
      } else {
        _brightness = (_brightness + delta).clamp(0, 1);
        ScreenBrightness.instance.setApplicationScreenBrightness(_brightness).catchError((_) {});
        _flash('LIGHT', _brightness);
      }
    } else {
      final s = Settings.i;
      final v = s.fontSize - d.delta.dy / 14;
      if (v.round() != s.fontSize.round()) haptic();
      s.fontSize = v.roundToDouble();
      _flash('SIZE ${s.fontSize.round()}', (s.fontSize - 11) / 29);
    }
  }

  // ------------------------------------------------------------ tap handling

  Offset? _downAt;
  DateTime? _downTime;

  void _onPointerUp(PointerUpEvent e) {
    _touching = false;
    final down = _downAt;
    final time = _downTime;
    if (down == null || time == null || _mode == ReadMode.swipe) return;
    if ((e.position - down).distance > 10 || DateTime.now().difference(time).inMilliseconds > 280) return;
    final h = MediaQuery.of(context).size.height;
    final y = e.position.dy;
    if (Settings.i.tapZones && _mode == ReadMode.scroll && _scroll.hasClients && !_hud) {
      if (y < h * .2) return _page(-1);
      if (y > h * .8) return _page(1);
    }
    _setHud(!_hud);
  }

  void _page(int dir) {
    final pos = _scroll.position;
    final target = (pos.pixels + dir * pos.viewportDimension * .86).clamp(0.0, pos.maxScrollExtent);
    _scroll.animateTo(target, duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
    haptic();
  }

  // ------------------------------------------------------------ read along

  bool _follow = true;
  int? _followBlock;
  DateTime _lastFollow = DateTime(0);

  /// Where the narration is, as a fraction of this book. When the audiobook's
  /// tracks line up with the book's chapters, each track maps to its chapter;
  /// otherwise the whole recording maps onto the whole text.
  double? _audioFraction() {
    final a = widget.follow;
    final d = _doc;
    if (a == null || d == null || d.blocks.isEmpty || a.tracks.isEmpty || Player.i.book?.id != a.id) return null;
    final n = a.tracks.length;
    final idx = a.trackIndex.clamp(0, n - 1);
    final cur = a.tracks[idx];
    final within = cur.ms > 0 ? (Player.i.position.inMilliseconds / cur.ms).clamp(0.0, 1.0) : 0.0;
    final chapters = d.toc.where((e) => e.depth == 0).toList();
    if (n > 1 && d.wordCount > 0 && chapters.length >= n && chapters.length <= n + 3) {
      // Extra entries up front are usually title page / contents with no narration.
      final c = idx + chapters.length - n;
      final from = d.wordOffsets[chapters[c].block.clamp(0, d.blocks.length)];
      final to = c + 1 < chapters.length ? d.wordOffsets[chapters[c + 1].block.clamp(0, d.blocks.length)] : d.wordCount;
      return (from + within * (to - from)) / d.wordCount;
    }
    if (a.timed) return (a.elapsedMs / a.totalMs).clamp(0.0, 1.0);
    return ((idx + within) / n).clamp(0.0, 1.0);
  }

  void _onAudio() {
    if (!mounted || _doc == null) return;
    final now = DateTime.now();
    if (now.difference(_lastFollow).inMilliseconds < 1200) return;
    _lastFollow = now;
    final f = _audioFraction();
    if (f == null) return;
    final block = _blockAt(f);
    if (block != _followBlock) setState(() => _followBlock = block);
    // Leave the page alone while the reader is touching or just scrolled.
    if (!_follow || _mode != ReadMode.scroll || _touching || now.difference(_lastInteract).inSeconds < 6) return;
    final d = _doc!;
    final drift = ((f - _progress) * d.wordCount).abs();
    if (d.wordCount > 0 && drift < 30) return;
    _followTo(f);
  }

  /// Glides to fraction [f] if it is nearby, jumps if it is not.
  void _followTo(double f) {
    final d = _doc!;
    final block = _blockAt(f);
    final words = d.blocks[block].words;
    final inner = d.wordCount == 0 || words == 0 ? 0.0 : ((f * d.wordCount - d.wordOffsets[block]) / words).clamp(0.0, 1.0);
    final box = _items[block]?.findRenderObject();
    if (box is RenderBox && box.attached && box.hasSize && _scroll.hasClients) {
      final top = box.localToGlobal(Offset.zero).dy;
      final target = (_scroll.position.pixels + (top - _readLine) + inner * box.size.height).clamp(0.0, _scroll.position.maxScrollExtent);
      _scroll.animateTo(target, duration: const Duration(milliseconds: 700), curve: Curves.easeInOutCubic);
    } else {
      _jumpTo(block, inner: inner);
    }
  }

  Widget _followBar(BuildContext context) {
    final t = Tokens.of(context);
    return Positioned(
      left: 12,
      right: 12,
      bottom: MediaQuery.of(context).padding.bottom + (_hud ? 160 : 14),
      child: ListenableBuilder(
        listenable: Player.i,
        builder: (context, _) {
          final pl = Player.i;
          final a = widget.follow!;
          final live = pl.book?.id == a.id;
          return Container(
            padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
            decoration: BoxDecoration(
              color: t.surface.withValues(alpha: .97),
              borderRadius: BorderRadius.circular(t.zen ? 14 : t.radius + 4),
              border: t.zen ? null : Border.all(color: t.line),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .15), blurRadius: 16, offset: const Offset(0, 4))],
            ),
            child: Row(children: [
              IconButton(onPressed: () => live ? pl.skip(-10) : pl.open(a), icon: const Icon(Icons.replay_10_sharp)),
              IconButton(
                onPressed: () => live ? pl.toggle() : pl.open(a),
                icon: Icon(live && pl.playing ? Icons.pause_sharp : Icons.play_arrow_sharp, color: t.accent, size: 28),
              ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(a.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  Label(live ? (pl.current?.title ?? '') : 'Paused', size: 9),
                ]),
              ),
              GestureDetector(
                onTap: () {
                  haptic();
                  setState(() => _follow = !_follow);
                  if (_follow) {
                    _lastInteract = DateTime(0);
                    _lastFollow = DateTime(0);
                    _onAudio();
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(color: _follow ? t.accent.withValues(alpha: .15) : Colors.transparent, borderRadius: BorderRadius.circular(10)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(_follow ? Icons.sync_sharp : Icons.sync_disabled_sharp, size: 16, color: _follow ? t.accent : t.muted),
                    const SizedBox(width: 4),
                    Label('Follow', color: _follow ? t.accent : t.muted, weight: FontWeight.w600),
                  ]),
                ),
              ),
            ]),
          );
        },
      ),
    );
  }

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Settings.i,
      builder: (context, _) {
        final s = Settings.i;
        final systemDark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
        final surface = s.surfaceFor(systemDark);
        final style = ReaderStyle.of(s, surface);
        final overlayStyle = surface.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark;

        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: overlayStyle.copyWith(statusBarColor: Colors.transparent),
          child: Scaffold(
            backgroundColor: surface.bg,
            body: Stack(children: [
              Positioned.fill(
                child: Listener(
                  onPointerDown: (e) {
                    _touching = true;
                    _downAt = e.position;
                    _downTime = DateTime.now();
                    _lastInteract = DateTime.now();
                  },
                  onPointerUp: _onPointerUp,
                  onPointerCancel: (_) => _touching = false,
                  child: _body(context, style),
                ),
              ),
              // light filters
              if (s.warmth > 0) IgnorePointer(child: Container(color: const Color(0xFFFF8A00).withValues(alpha: s.warmth * .45))),
              if (s.dim > 0) IgnorePointer(child: Container(color: Colors.black.withValues(alpha: s.dim))),
              ..._edges(s),
              if (!_hud && s.showReaderHud && _doc != null && _mode == ReadMode.scroll) _statusLine(context, style),
              // In fullscreen the speed pill hides too; tap to bring both back.
              if (_auto && _hud) _autoPill(context, style),
              if (_overlay != null) _overlayMeter(context, style),
              if (widget.follow != null) _followBar(context),
              // Like the auto-scroll pill: only with the controls up, not in fullscreen.
              if (_speakingBlock != null && _hud) _readBar(context),
              _topBar(context, style),
              _bottomBar(context, style),
            ]),
          ),
        );
      },
    );
  }

  List<Widget> _edges(Settings s) {
    if (_mode == ReadMode.pdf) return const [];
    Widget strip(bool left, bool brightness) => Positioned(
          left: left ? 0 : null,
          right: left ? null : 0,
          top: 90,
          bottom: 90,
          width: 26,
          child: GestureDetector(behavior: HitTestBehavior.translucent, onVerticalDragUpdate: (d) => _edgeDrag(d, brightness)),
        );
    final out = <Widget>[];
    bool on(EdgeSide e, bool left) => e == EdgeSide.both || (left ? e == EdgeSide.left : e == EdgeSide.right);
    for (final left in [true, false]) {
      if (on(s.brightnessEdge, left)) {
        out.add(strip(left, true));
      } else if (on(s.fontSizeEdge, left)) {
        out.add(strip(left, false));
      }
    }
    return out;
  }

  Widget _body(BuildContext context, ReaderStyle style) {
    if (_error != null) {
      return Center(child: Padding(padding: const EdgeInsets.all(32), child: Text('Could not open this file.\n$_error', style: style.body, textAlign: TextAlign.center)));
    }
    final d = _doc;
    if (d == null) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 1.5, color: Settings.i.signalOn(style.surface.fg))),
        const SizedBox(height: 14),
        Text('PARSING ${book.formatLabel}', style: monoFont(color: style.muted, fontSize: 10, letterSpacing: 1.4)),
      ]));
    }

    switch (_mode) {
      case ReadMode.pdf:
        return _pdfView(context, style, d);
      case ReadMode.swipe:
        return SwipeReader(
          key: _swipeKey,
          book: book,
          doc: d,
          style: style,
          startBlock: _current,
          onBlock: _setCurrent,
          onSelection: _onSelection,
          onBookmark: _toggleBookmark,
          onSpeak: _sayOnce,
          onTapCenter: () => _setHud(!_hud),
          turns: _swipeTurns.stream,
        );
      case ReadMode.scroll:
        return ListenableBuilder(
          listenable: Library.i,
          builder: (context, _) {
            final byBlock = <int, List<Highlight>>{};
            for (final h in Library.i.highlights) {
              if (h.bookId == book.id) (byBlock[h.block] ??= []).add(h);
            }
            final marks = {for (final b in Library.i.bookmarks) if (b.bookId == book.id) b.block};
            final top = MediaQuery.of(context).padding.top;
            return Scrollbar(
              controller: _scroll,
              thickness: 3,
              child: SuperListView.builder(
                controller: _scroll,
                listController: _list,
                padding: EdgeInsets.only(top: top + 56, bottom: MediaQuery.of(context).size.height * .45),
                itemCount: d.blocks.length,
                itemBuilder: (context, i) => _Probe(
                  index: i,
                  items: _items,
                  child: BlockView(
                  block: d.blocks[i],
                  index: i,
                  style: style,
                  highlights: byBlock[i] ?? const [],
                  onSelection: _onSelection,
                  search: _search,
                  speaking: _speakingBlock == i || _followBlock == i,
                  bookmarked: marks.contains(i),
                  ),
                ),
              ),
            );
          },
        );
    }
  }

  Widget _pdfView(BuildContext context, ReaderStyle style, ParsedDoc d) {
    _pdf ??= PdfViewerController();
    final page = d.blocks.isEmpty ? (book.position + 1) : ((d.blocks[_current].page ?? 0) + 1);
    final viewer = PdfViewer.file(
      book.path,
      controller: _pdf,
      initialPageNumber: page,
      params: PdfViewerParams(
        backgroundColor: style.surface.bg,
        margin: 10,
        pageDropShadow: null,
        onPageChanged: (p) {
          if (p == null) return;
          final idx = d.blocks.isEmpty ? p - 1 : d.blocks.indexWhere((b) => (b.page ?? 0) >= p - 1);
          if (idx >= 0) _setCurrent(idx);
        },
      ),
    );
    if (!style.surface.dark) return viewer;
    // Night: invert page colours, keep hue.
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix([-0.85, 0, 0, 0, 230, 0, -0.85, 0, 0, 230, 0, 0, -0.85, 0, 230, 0, 0, 0, 1, 0]),
      child: viewer,
    );
  }

  Widget _statusLine(BuildContext context, ReaderStyle style) {
    final d = _doc!;
    final ch = d.chapterAt(_current);
    final now = DateTime.now();
    final st = monoFont(color: style.muted, fontSize: 9.5, letterSpacing: 1);
    return Positioned(
      left: style.margin,
      right: style.margin,
      bottom: MediaQuery.of(context).padding.bottom + 10,
      child: IgnorePointer(
        child: Row(children: [
          Expanded(child: Text(caps(ch?.title ?? book.title), maxLines: 1, overflow: TextOverflow.ellipsis, style: st)),
          const SizedBox(width: 12),
          Text('${(_progress * 100).toStringAsFixed(1)}%', style: st),
          if (Settings.i.showClock) ...[const SizedBox(width: 12), Text('${pad(now.hour)}:${pad(now.minute)}', style: st)],
        ]),
      ),
    );
  }

  Widget _overlayMeter(BuildContext context, ReaderStyle style) {
    final t = Tokens.of(context);
    final v = (_overlayValue ?? 0).abs().clamp(0.0, 1.0);
    return Center(
      child: IgnorePointer(
        child: Container(
          width: 150,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: t.ink.withValues(alpha: .88), borderRadius: t.br),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_overlay!, style: monoFont(color: t.bg, fontSize: 11, letterSpacing: 1.4, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            Row(children: [
              for (var i = 0; i < 16; i++) Expanded(child: Container(height: 10, margin: const EdgeInsets.only(right: 2), color: i < (v * 16).round() ? t.accent : t.bg.withValues(alpha: .2))),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _autoPill(BuildContext context, ReaderStyle style) {
    final t = Tokens.of(context);
    final s = Settings.i;
    Widget b(IconData i, VoidCallback f) => GestureDetector(
          onTap: () {
            haptic();
            f();
          },
          child: Padding(padding: const EdgeInsets.all(10), child: Icon(i, size: 18, color: t.bg)),
        );
    return Positioned(
      left: 0,
      right: 0,
      bottom: MediaQuery.of(context).padding.bottom + (_hud ? 150 : 34),
      child: Center(
        child: Container(
          decoration: BoxDecoration(color: t.ink.withValues(alpha: .92), borderRadius: BorderRadius.circular(t.radius + 6)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            b(Icons.remove_sharp, () => s.autoScrollSpeed = s.autoScrollSpeed - (s.autoScrollSpeed > 60 ? 10 : 3)),
            SizedBox(
              width: 74,
              child: Column(children: [
                Text('${s.autoScrollSpeed.round()}', style: monoFont(color: t.bg, fontSize: 15, fontWeight: FontWeight.w600)),
                Text('PX/S', style: monoFont(color: t.bg.withValues(alpha: .6), fontSize: 8, letterSpacing: 1)),
              ]),
            ),
            b(Icons.add_sharp, () => s.autoScrollSpeed = s.autoScrollSpeed + (s.autoScrollSpeed >= 60 ? 10 : 3)),
            Container(width: 1, height: 22, color: t.bg.withValues(alpha: .2)),
            b(Icons.stop_sharp, _toggleAuto),
          ]),
        ),
      ),
    );
  }

  Widget _topBar(BuildContext context, ReaderStyle style) {
    final t = Tokens.of(context);
    final d = _doc;
    final ch = d?.chapterAt(_current);
    final marked = Library.i.bookmarkAt(book.id, _current) != null;
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      left: 0,
      right: 0,
      top: _hud ? 0 : -140,
      child: Container(
        padding: EdgeInsets.fromLTRB(8, MediaQuery.of(context).padding.top + 4, 8, 8),
        decoration: BoxDecoration(color: t.bg.withValues(alpha: .97), border: t.zen ? null : Border(bottom: BorderSide(color: t.line))),
        child: Row(children: [
          IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_sharp)),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
              Label(ch?.title ?? book.formatLabel, size: 9),
            ]),
          ),
          IconButton(onPressed: () => _openNavigator(tab: 3), icon: const Icon(Icons.search_sharp)),
          IconButton(onPressed: () => _openNavigator(), icon: const Icon(Icons.format_list_bulleted_sharp)),
          IconButton(onPressed: _toggleBookmark, icon: Icon(marked ? Icons.bookmark_sharp : Icons.bookmark_border_sharp, color: marked ? t.accent : null)),
          PopupMenuButton<String>(
            icon: Icon(Icons.auto_awesome_outlined, color: t.accent),
            onSelected: (v) async {
              if (d == null || !await ensureAi(context) || !context.mounted) return;
              switch (v) {
                case 'chat':
                  openAiChat(context, book, passage: _contextAround(_current));
                case 'recap':
                  showAiStream(context, title: 'Recap', subtitle: d.chapterAt(_current)?.title, book: book, make: () => Ai.recap(book, d, _current));
                case 'about':
                  showAiStream(context, title: 'About this book', subtitle: book.title, book: book, make: () => Ai.aboutBook(book, doc: d));
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'chat', child: Label('Chat about the book', color: t.ink)),
              PopupMenuItem(value: 'recap', child: Label('Recap what I read', color: t.ink)),
              PopupMenuItem(value: 'about', child: Label('What is this book?', color: t.ink)),
            ],
          ),
        ]),
      ),
    );
  }

  Widget _bottomBar(BuildContext context, ReaderStyle style) {
    final t = Tokens.of(context);
    final d = _doc;
    final at = _drag == null ? _current : _blockAt(_drag!);
    final ch = d?.chapterAt(at);
    final wordsLeft = d == null ? 0 : d.wordCount - _wordsBefore(d, at);
    final minsLeft = (wordsLeft / 230).round();
    Widget tool(IconData i, String l, VoidCallback f, {bool on = false}) => Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              haptic();
              f();
            },
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 42,
                height: 36,
                decoration: BoxDecoration(color: on ? t.accent : (t.zen ? t.raised : Colors.transparent), borderRadius: t.zen ? BorderRadius.circular(10) : t.br, border: t.zen ? null : Border.all(color: on ? t.accent : t.line)),
                child: Icon(i, size: 18, color: on ? t.onAccent : t.ink),
              ),
              const SizedBox(height: 4),
              Label(l, size: 8.5),
            ]),
          ),
        );

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      left: 0,
      right: 0,
      bottom: _hud ? 0 : -220,
      child: Container(
        padding: EdgeInsets.fromLTRB(16, 10, 16, MediaQuery.of(context).padding.bottom + 10),
        decoration: BoxDecoration(color: t.bg.withValues(alpha: .97), border: t.zen ? null : Border(top: BorderSide(color: t.line))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Label('${((_drag ?? _progress) * 100).toStringAsFixed(1)}%', color: _drag == null ? t.ink : t.accent, weight: FontWeight.w700),
            const SizedBox(width: 10),
            Expanded(child: Label(ch?.title ?? '', size: 9, color: _drag == null ? null : t.ink)),
            Label('~${fmtDuration(minsLeft * 60)} left', size: 9),
          ]),
          if (_mode != ReadMode.pdf)
            Slider(
              value: (_drag ?? _progress).clamp(0.0, 1.0),
              onChanged: (v) {
                setState(() => _drag = v);
                // Scrub the page live in scroll mode, a few times a second.
                if (_mode == ReadMode.scroll && DateTime.now().difference(_lastScrub).inMilliseconds > 70) {
                  _lastScrub = DateTime.now();
                  _jumpToFraction(v);
                }
              },
              onChangeEnd: (v) {
                _jumpToFraction(v);
                setState(() => _drag = null);
              },
            )
          else
            const SizedBox(height: 10),
          Row(children: [
            tool(Icons.text_fields_sharp, 'Type', () => _sheet((_) => const TypeControls(), title: 'Type')),
            tool(Icons.contrast_sharp, 'Light', () => _sheet((_) => const LightControls(), title: 'Light & surface')),
            tool(Settings.i.night ? Icons.dark_mode_sharp : Icons.light_mode_outlined, 'Night', () => Settings.i.night = !Settings.i.night, on: Settings.i.night),
            tool(Icons.keyboard_double_arrow_down_sharp, 'Auto', _toggleAuto, on: _auto),
            tool(Icons.swipe_vertical_outlined, 'Swipe', () => _setMode(_mode == ReadMode.swipe ? ReadMode.scroll : ReadMode.swipe), on: _mode == ReadMode.swipe),
            tool(_speakingBlock != null ? Icons.stop_sharp : Icons.graphic_eq_sharp, 'Listen', _toggleListen, on: _speakingBlock != null),
            if (book.format == BookFormat.pdf) tool(Icons.picture_as_pdf_outlined, 'Page', () => _setMode(_mode == ReadMode.pdf ? ReadMode.scroll : ReadMode.pdf), on: _mode == ReadMode.pdf),
            tool(Icons.tune_sharp, 'More', () => _sheet((_) => const MotionControls(), title: 'Motion & gestures')),
          ]),
        ]),
      ),
    );
  }
}

/// Registers a list item's context under its index while it is laid out.
class _Probe extends StatefulWidget {
  const _Probe({required this.index, required this.items, required this.child});
  final int index;
  final Map<int, BuildContext> items;
  final Widget child;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    widget.items[widget.index] = context;
  }

  @override
  void didUpdateWidget(_Probe old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) {
      if (identical(widget.items[old.index], context)) widget.items.remove(old.index);
      widget.items[widget.index] = context;
    }
  }

  @override
  void dispose() {
    if (identical(widget.items[widget.index], context)) widget.items.remove(widget.index);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
