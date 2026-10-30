import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/settings.dart';
import '../models/annotations.dart';
import '../models/book.dart';
import 'audio.dart';
import 'library.dart';
import 'podcasts.dart';

const widgetKinds = ['books', 'audio', 'podcasts', 'all'];

const widgetKindNames = {'books': 'Books', 'audio': 'Audio', 'podcasts': 'Podcasts', 'all': 'All'};

/// Time totals for one kind of session.
class ScopeStats {
  const ScopeStats({this.today = 0, this.week = 0, this.total = 0, this.streak = 0});

  /// Seconds.
  final int today;
  final int week;
  final int total;

  /// Days in a row with at least a minute, counting back from today (or
  /// yesterday, so a streak survives until today is over).
  final int streak;

  factory ScopeStats.compute(Iterable<ReadingSession> sessions, DateTime now) {
    DateTime day(DateTime d) => DateTime(d.year, d.month, d.day);
    final perDay = <DateTime, int>{};
    var total = 0;
    for (final s in sessions) {
      perDay.update(day(s.start), (v) => v + s.seconds, ifAbsent: () => s.seconds);
      total += s.seconds;
    }
    final today = day(now);
    var week = 0;
    for (var i = 0; i < 7; i++) {
      week += perDay[DateTime(today.year, today.month, today.day - i)] ?? 0;
    }
    var streak = 0;
    var d = (perDay[today] ?? 0) >= 60 ? today : DateTime(today.year, today.month, today.day - 1);
    while ((perDay[d] ?? 0) >= 60) {
      streak++;
      d = DateTime(d.year, d.month, d.day - 1);
    }
    return ScopeStats(today: perDay[today] ?? 0, week: week, total: total, streak: streak);
  }
}

/// What a widget displays.
class WidgetData {
  const WidgetData({required this.books, required this.audio, required this.podcasts, required this.all, required this.goalMinutes, required this.booksDone, required this.audioDone, required this.episodesDone});
  final ScopeStats books;
  final ScopeStats audio;
  final ScopeStats podcasts;
  final ScopeStats all;
  final int goalMinutes;
  final int booksDone;
  final int audioDone;
  final int episodesDone;

  ScopeStats of(String kind) => switch (kind) { 'books' => books, 'audio' => audio, 'podcasts' => podcasts, _ => all };

  (int, String) doneOf(String kind) => switch (kind) {
        'books' => (booksDone, 'finished'),
        'audio' => (audioDone, 'finished'),
        'podcasts' => (episodesDone, 'played'),
        _ => (booksDone + audioDone + episodesDone, 'finished'),
      };

  factory WidgetData.current([DateTime? at]) {
    final now = at ?? DateTime.now();
    final s = Library.i.sessions;
    return WidgetData(
      books: ScopeStats.compute(s.where((x) => !x.listening), now),
      audio: ScopeStats.compute(s.where((x) => x.mode == 'audiobook'), now),
      podcasts: ScopeStats.compute(s.where((x) => x.mode == 'podcast' || x.mode == 'radio'), now),
      all: ScopeStats.compute(s, now),
      goalMinutes: Settings.i.dailyGoalMinutes,
      booksDone: Library.i.books.where((b) => b.status == ReadStatus.finished).length,
      audioDone: AudioLibrary.i.books.where((b) => b.finished).length,
      episodesDone: Podcasts.i.states.values.where((x) => x.played).length,
    );
  }
}

/// How a widget looks. Null colours follow the defaults below.
class WidgetStyle {
  WidgetStyle({
    this.background,
    this.text,
    this.accent,
    this.font = 'Inter',
    this.opacity = 1,
    this.radius = 20,
    this.showGoal = true,
    this.showWeek = true,
    this.showStreak = true,
    this.showDone = true,
    this.showTitle = true,
  });

  Color? background;
  Color? text;
  Color? accent;
  String font;
  double opacity;
  double radius;
  bool showGoal;
  bool showWeek;
  bool showStreak;
  bool showDone;
  bool showTitle;

  Color get bg => background ?? const Color(0xFF17171A);

  /// Readable on the background unless chosen otherwise.
  Color get fg => text ?? (bg.computeLuminance() > .45 ? const Color(0xFF17171A) : const Color(0xFFF4F4F5));
  Color get signal => accent ?? Settings.i.signalOn(fg);

  Map<String, dynamic> toJson() => {
        if (background != null) 'background': background!.toARGB32(),
        if (text != null) 'text': text!.toARGB32(),
        if (accent != null) 'accent': accent!.toARGB32(),
        'font': font,
        'opacity': opacity,
        'radius': radius,
        'showGoal': showGoal,
        'showWeek': showWeek,
        'showStreak': showStreak,
        'showDone': showDone,
        'showTitle': showTitle,
      };

  factory WidgetStyle.fromJson(Map<String, dynamic> j) {
    Color? c(String k) => j[k] is int ? Color(j[k]) : null;
    return WidgetStyle(
      background: c('background'),
      text: c('text'),
      accent: c('accent'),
      font: j['font'] ?? 'Inter',
      opacity: (j['opacity'] ?? 1).toDouble(),
      radius: (j['radius'] ?? 20).toDouble(),
      showGoal: j['showGoal'] ?? true,
      showWeek: j['showWeek'] ?? true,
      showStreak: j['showStreak'] ?? true,
      showDone: j['showDone'] ?? true,
      showTitle: j['showTitle'] ?? true,
    );
  }

  static WidgetStyle of(String kind) => WidgetStyle.fromJson(Settings.i.widgetStyle(kind));
}

String _time(int seconds) {
  final m = seconds ~/ 60;
  if (m < 60) return '${m}m';
  return '${m ~/ 60}h ${(m % 60).toString().padLeft(2, '0')}';
}

/// Draws a widget. The same code paints the customiser's preview and the image
/// the home screen shows, so what you see is what you get.
class StatWidgetPainter extends CustomPainter {
  StatWidgetPainter({required this.kind, required this.data, required this.style});
  final String kind;
  final WidgetData data;
  final WidgetStyle style;

  TextPainter _layout(String text, double size, Color color, {FontWeight weight = FontWeight.w500, double? maxWidth}) {
    TextStyle ts;
    try {
      ts = GoogleFonts.getFont(style.font, fontSize: size, color: color, fontWeight: weight, height: 1.1);
    } catch (_) {
      ts = TextStyle(fontSize: size, color: color, fontWeight: weight, height: 1.1);
    }
    return TextPainter(text: TextSpan(text: text, style: ts), textDirection: TextDirection.ltr, maxLines: 1, ellipsis: '…')..layout(maxWidth: maxWidth ?? double.infinity);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(style.radius));
    canvas.drawRRect(rect, Paint()..color = style.bg.withValues(alpha: style.opacity));
    canvas.save();
    canvas.clipRRect(rect);
    kind == 'all' ? _paintAll(canvas, size) : _paintOne(canvas, size);
    canvas.restore();
  }

  void _bar(Canvas canvas, Offset at, double width, double height, double value) {
    final r = Radius.circular(height / 2);
    canvas.drawRRect(RRect.fromRectAndRadius(at & Size(width, height), r), Paint()..color = style.fg.withValues(alpha: .16));
    if (value > 0) canvas.drawRRect(RRect.fromRectAndRadius(at & Size(width * value.clamp(.02, 1), height), r), Paint()..color = style.signal);
  }

  /// A value with a small label under it.
  void _fact(Canvas canvas, Offset at, String value, String label, double k, double maxWidth) {
    final v = _layout(value, 15 * k, style.fg, weight: FontWeight.w700, maxWidth: maxWidth);
    v.paint(canvas, at);
    _layout(label, 10 * k, style.fg.withValues(alpha: .62), maxWidth: maxWidth).paint(canvas, at + Offset(0, v.height + 1));
  }

  void _paintOne(Canvas canvas, Size size) {
    final k = (size.shortestSide / 160).clamp(.62, 1.5);
    final pad = 14.0 * k;
    final w = size.width - pad * 2;
    final d = data.of(kind);
    var y = pad;
    if (style.showTitle) {
      final title = _layout(widgetKindNames[kind]!.toUpperCase(), 10.5 * k, style.signal, weight: FontWeight.w700, maxWidth: w);
      title.paint(canvas, Offset(pad, y));
      y += title.height + 6 * k;
    }
    final big = _layout(_time(d.today), 34 * k, style.fg, weight: FontWeight.w700, maxWidth: w);
    big.paint(canvas, Offset(pad, y));
    y += big.height;
    final today = _layout('today', 11 * k, style.fg.withValues(alpha: .62), maxWidth: w);
    today.paint(canvas, Offset(pad, y));
    y += today.height + 8 * k;
    if (style.showGoal && y + 6 * k < size.height - pad) {
      _bar(canvas, Offset(pad, y), w, 6 * k, data.goalMinutes == 0 ? 0 : d.today / 60 / data.goalMinutes);
    }

    final facts = <(String, String)>[
      if (style.showWeek) (_time(d.week), 'this week'),
      if (style.showStreak) ('${d.streak}', 'day streak'),
      if (style.showDone) ('${data.doneOf(kind).$1}', data.doneOf(kind).$2),
    ];
    final factH = 30 * k;
    if (facts.isNotEmpty && size.height - pad - factH > y + 8 * k) {
      final col = w / facts.length;
      for (final (i, f) in facts.indexed) {
        _fact(canvas, Offset(pad + col * i, size.height - pad - factH), f.$1, f.$2, k, col - 4);
      }
    }
  }

  void _paintAll(Canvas canvas, Size size) {
    final k = (size.width / 320).clamp(.62, 1.5) * (size.height < 120 ? .8 : 1);
    final pad = 14.0 * k;
    final w = size.width - pad * 2;
    final d = data.all;
    var y = pad;

    // Today's total, with the streak on the right.
    if (style.showTitle) {
      final title = _layout('TODAY', 10.5 * k, style.signal, weight: FontWeight.w700, maxWidth: w / 2);
      title.paint(canvas, Offset(pad, y));
      y += title.height + 3 * k;
    }
    final big = _layout(_time(d.today), 30 * k, style.fg, weight: FontWeight.w700, maxWidth: w * .6);
    big.paint(canvas, Offset(pad, y));
    if (style.showStreak) {
      final v = _layout('${d.streak}', 20 * k, style.fg, weight: FontWeight.w700);
      final l = _layout('day streak', 10 * k, style.fg.withValues(alpha: .62));
      final top = y + (big.height - v.height - l.height) / 2;
      v.paint(canvas, Offset(size.width - pad - v.width, top));
      l.paint(canvas, Offset(size.width - pad - l.width, top + v.height));
    }
    y += big.height + 7 * k;
    if (style.showGoal) {
      _bar(canvas, Offset(pad, y), w, 6 * k, data.goalMinutes == 0 ? 0 : d.today / 60 / data.goalMinutes);
      y += 6 * k + 8 * k;
    }

    // One column each.
    final col = w / 3;
    final rows = [('Books', data.books, 'books'), ('Audio', data.audio, 'audio'), ('Podcasts', data.podcasts, 'podcasts')];
    final colH = (style.showWeek ? 13 * k : 0) + 32 * k + (style.showDone ? 13 * k : 0);
    final top = size.height - pad - colH;
    if (top < y - 4 * k) return;
    for (final (i, r) in rows.indexed) {
      final x = pad + col * i;
      var cy = top;
      final name = _layout(r.$1, 10 * k, style.signal, weight: FontWeight.w700, maxWidth: col - 4);
      name.paint(canvas, Offset(x, cy));
      cy += name.height + 2 * k;
      final v = _layout(_time(r.$2.today), 16 * k, style.fg, weight: FontWeight.w700, maxWidth: col - 4);
      v.paint(canvas, Offset(x, cy));
      cy += v.height + 1;
      if (style.showWeek) {
        final week = _layout('${_time(r.$2.week)} week', 9.5 * k, style.fg.withValues(alpha: .62), maxWidth: col - 4);
        week.paint(canvas, Offset(x, cy));
        cy += week.height + 1;
      }
      if (style.showDone) {
        final done = data.doneOf(r.$3);
        _layout('${done.$1} ${done.$2}', 9.5 * k, style.fg.withValues(alpha: .62), maxWidth: col - 4).paint(canvas, Offset(x, cy));
      }
    }
  }

  @override
  bool shouldRepaint(StatWidgetPainter old) => true;
}

/// Keeps the home-screen widgets' images current.
///
/// Android widgets can only use a few system fonts, so each widget is painted
/// here to a PNG (any font, any colour), and the native side just shows it.
class StatWidgets with WidgetsBindingObserver {
  StatWidgets._();
  static final StatWidgets i = StatWidgets._();

  static const _channel = MethodChannel('alexandria/widgets');
  Timer? _pending;
  bool _busy = false;

  void init() {
    if (!Platform.isAndroid) return;
    _channel.setMethodCallHandler((call) async {
      // A widget was added or resized.
      if (call.method == 'changed') schedule(const Duration(seconds: 1));
    });
    WidgetsBinding.instance.addObserver(this);
    final any = Listenable.merge([Library.i, AudioLibrary.i, Podcasts.i, Settings.i]);
    any.addListener(() => schedule(const Duration(seconds: 45)));
    schedule(const Duration(seconds: 2));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) schedule(const Duration(seconds: 1));
    // Leaving the app: this is the last chance to show today's newest numbers.
    if (state == AppLifecycleState.hidden) refresh();
  }

  /// Refreshes after [delay]; a run already waiting is left alone, so a stream
  /// of changes (like playback progress) can't keep pushing it back.
  void schedule(Duration delay) {
    if (_pending?.isActive ?? false) {
      if (delay.inSeconds > 2) return;
      _pending!.cancel();
    }
    _pending = Timer(delay, refresh);
  }

  /// The widgets on the home screen, by kind, with their size in dp.
  Future<Map<String, Size>> _installed() async {
    final r = await _channel.invokeMethod<Map>('sizes');
    return {
      for (final e in (r ?? const {}).entries)
        if (e.value is List) '${e.key}': Size(((e.value as List)[0] as num).toDouble(), ((e.value as List)[1] as num).toDouble()),
    };
  }

  static Size defaultSize(String kind) => kind == 'all' ? const Size(320, 170) : const Size(170, 170);

  /// Redraws every placed widget.
  Future<void> refresh() async {
    if (_busy || !Platform.isAndroid) return;
    _busy = true;
    try {
      final sizes = await _installed();
      for (final e in sizes.entries) {
        await _render(e.key, e.value);
        await _channel.invokeMethod('refresh', {'kind': e.key});
      }
    } catch (e) {
      debugPrint('[widgets] refresh failed: $e');
    } finally {
      _busy = false;
    }
  }

  Future<void> _render(String kind, Size size) async {
    final style = WidgetStyle.of(kind);
    try {
      await GoogleFonts.pendingFonts([GoogleFonts.getFont(style.font)]).timeout(const Duration(seconds: 8));
    } catch (_) {} // offline with an uncached font: fall back to the default face
    final w = size.width <= 0 ? defaultSize(kind).width : size.width;
    final h = size.height <= 0 ? defaultSize(kind).height : size.height;
    const px = 2.5; // sharp on most screens, small enough for a widget update
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec)..scale(px);
    StatWidgetPainter(kind: kind, data: WidgetData.current(), style: style).paint(canvas, Size(w, h));
    final image = await rec.endRecording().toImage((w * px).round(), (h * px).round());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final dir = Directory(p.join((await getApplicationSupportDirectory()).path, 'widgets'));
    await dir.create(recursive: true);
    final f = File(p.join(dir.path, '$kind.png'));
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
    await tmp.rename(f.path);
  }

  /// Asks the launcher to add a widget. False if it can't, and the user has to
  /// add it from the home screen's own widget menu.
  Future<bool> pin(String kind) async {
    if (!Platform.isAndroid) return false;
    await _render(kind, defaultSize(kind));
    return await _channel.invokeMethod<bool>('pin', {'kind': kind}) ?? false;
  }
}
