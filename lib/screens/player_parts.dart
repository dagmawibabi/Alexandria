import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/theme.dart';
import '../core/ui.dart';
import '../models/audiobook.dart';
import '../services/audio.dart';
import '../services/podcasts.dart';
import '../services/radio.dart';
import 'audiobook_screen.dart';
import 'player_screen.dart';
import 'podcasts_view.dart';
import 'radio_view.dart';

// Pieces shared by the player and its full-screen view.

/// What tapping the title in the player opens: the show, the station or the
/// audiobook. Null when there's nowhere to go.
VoidCallback? openSourceAction(BuildContext context, Audiobook b) {
  final nav = Navigator.of(context);
  // Close the player (and full screen) first, so the page opens over where you were.
  void leave() => nav.popUntil((r) => r.settings.name != PlayerScreen.route && r.settings.name != FullScreenPlayer.route);
  switch (b.source) {
    case 'podcast':
      final feed = Podcasts.i.episodeFor(b)?.feedUrl;
      if (feed == null || feed.isEmpty) return null;
      return () {
        leave();
        openPodcast(nav.context, feedUrl: feed);
      };
    case 'radio':
      final s = RadioDirectory.i.stationFor(b.sourceKey);
      if (s == null) return null;
      return () {
        leave();
        showStationMenu(nav.context, s);
      };
    default:
      final shelved = AudioLibrary.i.byId(b.id);
      if (shelved == null) return null;
      return () {
        leave();
        openAudiobook(nav.context, shelved);
      };
  }
}

/// Title and show/author, tappable to open where it came from.
class SourceTitle extends StatelessWidget {
  const SourceTitle({super.key, required this.book, this.onTap, this.color, this.muted, this.titleSize = 22});
  final Audiobook book;
  final VoidCallback? onTap;
  final Color? color;
  final Color? muted;
  final double titleSize;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final b = book;
    final sub = muted ?? t.muted;
    final podcast = b.source == 'podcast';
    final title = Text(
      b.title,
      textAlign: TextAlign.center,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: titleSize, fontWeight: FontWeight.w700, height: 1.15, letterSpacing: -.3, color: color),
    );
    // The show's name is the link for an episode; the title is for a book or station.
    final author = b.author.isEmpty
        ? null
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  b.author,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: onTap != null && podcast ? (color ?? t.ink) : sub, fontSize: 15, fontWeight: onTap != null && podcast ? FontWeight.w600 : FontWeight.w400),
                ),
              ),
              if (onTap != null) Icon(Icons.chevron_right_sharp, size: 18, color: sub),
            ],
          );
    return Semantics(
      button: onTap != null,
      hint: onTap == null ? null : (podcast ? 'Open the show' : (b.source == 'radio' ? 'Open the station' : 'Open the audiobook')),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap == null
            ? null
            : () {
                haptic();
                onTap!();
              },
        child: Column(
          children: [
            title,
            if (author != null) Padding(padding: const EdgeInsets.only(top: 4), child: author),
            if (author == null && onTap != null) Icon(Icons.chevron_right_sharp, size: 18, color: sub),
          ],
        ),
      ),
    );
  }
}

/// What a swipe on the cover does: chapters for a book, episodes for a show,
/// stations for radio.
({VoidCallback? next, VoidCallback? previous}) swipeActions(Audiobook b) {
  final pl = Player.i;
  switch (b.source) {
    case 'podcast':
      final e = Podcasts.i.episodeFor(b);
      if (e == null) return (next: null, previous: null);
      final n = Podcasts.i.neighbour(e, 1), p = Podcasts.i.neighbour(e, -1);
      return (next: n == null ? null : () => Podcasts.i.play(n), previous: p == null ? null : () => Podcasts.i.play(p));
    case 'radio':
      final n = RadioDirectory.i.neighbour(b.sourceKey, 1), p = RadioDirectory.i.neighbour(b.sourceKey, -1);
      return (next: n == null ? null : () => RadioDirectory.i.play(n), previous: p == null ? null : () => RadioDirectory.i.play(p));
    default:
      return (next: b.trackIndex < b.tracks.length - 1 ? () => pl.jumpTo(b.trackIndex + 1) : null, previous: b.trackIndex > 0 ? () => pl.jumpTo(b.trackIndex - 1) : null);
  }
}

/// The cover, which follows a horizontal swipe: left for the next chapter,
/// episode or station, right for the previous one.
class SwipeCover extends StatefulWidget {
  const SwipeCover({super.key, required this.book, required this.child, this.onTap});
  final Audiobook book;
  final Widget child;
  final VoidCallback? onTap;

  @override
  State<SwipeCover> createState() => _SwipeCoverState();
}

class _SwipeCoverState extends State<SwipeCover> with SingleTickerProviderStateMixin {
  late final _dx = AnimationController.unbounded(vsync: this);

  @override
  void initState() {
    super.initState();
    final e = widget.book.source == 'podcast' ? Podcasts.i.episodeFor(widget.book) : null;
    if (e != null) Podcasts.i.ensureFeed(e.feedUrl).ignore();
  }

  @override
  void dispose() {
    _dx.dispose();
    super.dispose();
  }

  /// The cover's width as last laid out. Asking the context for its size isn't
  /// allowed while building, so the build records it here instead.
  double _width = 300;

  void _drag(DragUpdateDetails d) {
    final a = swipeActions(widget.book);
    var v = _dx.value + d.delta.dx;
    // Nothing that way: give a little, then resist.
    if ((v < 0 && a.next == null) || (v > 0 && a.previous == null)) v = _dx.value + d.delta.dx * .25;
    _dx.value = v;
  }

  Future<void> _end(DragEndDetails d) async {
    final a = swipeActions(widget.book);
    final w = _width;
    final fling = d.velocity.pixelsPerSecond.dx;
    final go = _dx.value < -w * .25 || fling < -700 ? a.next : (_dx.value > w * .25 || fling > 700 ? a.previous : null);
    if (go == null) {
      await _dx.animateTo(0, duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic);
      return;
    }
    final left = _dx.value < 0 || (_dx.value == 0 && fling < 0);
    haptic(true);
    await _dx.animateTo(left ? -w * 1.1 : w * 1.1, duration: const Duration(milliseconds: 160), curve: Curves.easeIn);
    go();
    // The new cover slides in from the other side.
    _dx.value = left ? w * .6 : -w * .6;
    if (mounted) await _dx.animateTo(0, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragUpdate: _drag,
      onHorizontalDragEnd: _end,
      onTap: widget.onTap,
      child: LayoutBuilder(
        builder: (context, box) {
          if (box.hasBoundedWidth && box.maxWidth > 0) _width = box.maxWidth;
          return AnimatedBuilder(animation: _dx, builder: _frame, child: widget.child);
        },
      ),
    );
  }

  Widget _frame(BuildContext context, Widget? child) {
    final w = _width;
    final f = (_dx.value.abs() / w).clamp(0.0, 1.0);
    return Transform.translate(
      offset: Offset(_dx.value, 0),
      child: Transform.rotate(
        angle: _dx.value / w * .06,
        child: Opacity(opacity: 1 - f * .7, child: child),
      ),
    );
  }
}

/// The seek bar and times. Live radio shows its status instead.
class PlayerScrubber extends StatefulWidget {
  const PlayerScrubber({super.key, this.color, this.muted});
  final Color? color;
  final Color? muted;

  @override
  State<PlayerScrubber> createState() => _PlayerScrubberState();
}

class _PlayerScrubberState extends State<PlayerScrubber> {
  double? _drag;

  // Listens itself rather than relying on a parent to rebuild it: as a const
  // child (the normal player) a parent rebuild skips it, and the time stuck at 0:00.
  @override
  void initState() {
    super.initState();
    Player.i.ticks.addListener(_changed);
  }

  @override
  void dispose() {
    Player.i.ticks.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final pl = Player.i;
    final b = pl.book;
    if (b == null) return const SizedBox.shrink();
    if (b.source == 'radio') {
      return Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: pl.playing ? t.accent : (widget.muted ?? t.muted), shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Label(pl.loading ? 'Connecting' : (pl.playing ? 'Live' : 'Paused'), color: widget.color ?? t.ink, weight: FontWeight.w600),
          ],
        ),
      );
    }
    final dur = pl.duration > Duration.zero ? pl.duration : Duration(milliseconds: pl.current?.ms ?? 0);
    final pos = _drag != null ? Duration(milliseconds: (_drag! * dur.inMilliseconds).round()) : pl.position;
    final frac = dur.inMilliseconds == 0 ? 0.0 : (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0);
    Widget slider = Slider(
      value: frac,
      onChanged: dur == Duration.zero ? null : (v) => setState(() => _drag = v),
      onChangeEnd: (v) {
        pl.seek(Duration(milliseconds: (v * dur.inMilliseconds).round()));
        setState(() => _drag = null);
      },
    );
    if (widget.color != null) {
      slider = SliderTheme(
        data: SliderTheme.of(context).copyWith(activeTrackColor: widget.color, thumbColor: widget.color, inactiveTrackColor: widget.color!.withValues(alpha: .25), overlayColor: widget.color!.withValues(alpha: .12)),
        child: slider,
      );
    }
    return Column(
      children: [
        slider,
        Row(
          children: [
            Label(fmtClock(pos), color: widget.color ?? t.ink),
            const Spacer(),
            Label(dur == Duration.zero ? '--:--' : '-${fmtClock(dur - pos)}', color: widget.muted),
          ],
        ),
      ],
    );
  }
}

/// Previous, back 10 s, play, forward 30 s, next.
class PlayerControls extends StatelessWidget {
  const PlayerControls({super.key, this.color, this.disabled, this.scale = 1});
  final Color? color;
  final Color? disabled;
  final double scale;

  // Listens itself, like [PlayerScrubber]: a const parent rebuild would skip it,
  // leaving the play button on its loading spinner while audio plays.
  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: Listenable.merge([Player.i, Podcasts.i]), builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final t = Tokens.of(context);
    final pl = Player.i;
    final b = pl.book;
    if (b == null) return const SizedBox.shrink();
    final live = b.source == 'radio';
    final podcast = b.source == 'podcast';
    Widget round(IconData i, VoidCallback onTap, {double size = 48, bool enabled = true}) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled
          ? () {
              haptic();
              onTap();
            }
          : null,
      child: SizedBox(
        width: size * scale,
        height: size * scale,
        child: Icon(i, size: size * scale * .55, color: enabled ? (color ?? t.ink) : (disabled ?? t.line)),
      ),
    );
    final swipe = swipeActions(b);
    final play = 76 * scale;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        if (live) round(Icons.skip_previous_sharp, () => swipe.previous?.call(), size: 46, enabled: swipe.previous != null),
        if (!live) round(Icons.skip_previous_sharp, pl.previous, size: 46, enabled: b.tracks.length > 1 || pl.position.inSeconds > 3),
        if (!live) round(Icons.replay_10_sharp, () => pl.skip(-10), size: 52),
        GestureDetector(
          onTap: () {
            haptic(true);
            pl.toggle();
          },
          child: Container(
            width: play,
            height: play,
            decoration: BoxDecoration(
              color: t.accent,
              borderRadius: BorderRadius.circular(t.zen ? 22 * scale : t.radius + 6),
              boxShadow: [BoxShadow(color: t.accent.withValues(alpha: .3), blurRadius: 18, offset: const Offset(0, 6))],
            ),
            child: pl.loading
                ? Padding(
                    padding: EdgeInsets.all(26 * scale),
                    child: CircularProgressIndicator(strokeWidth: 2, color: t.onAccent),
                  )
                : Icon(pl.playing ? Icons.pause_sharp : Icons.play_arrow_sharp, size: 38 * scale, color: t.onAccent),
          ),
        ),
        if (!live) round(Icons.forward_30_sharp, () => pl.skip(30), size: 52),
        if (!live) podcast ? round(Icons.skip_next_sharp, () => Podcasts.i.queue.isEmpty ? null : Podcasts.i.play(Podcasts.i.queue.first), size: 46, enabled: Podcasts.i.queue.isNotEmpty) : round(Icons.skip_next_sharp, pl.next, size: 46, enabled: b.trackIndex < b.tracks.length - 1),
        if (live) round(Icons.skip_next_sharp, () => swipe.next?.call(), size: 46, enabled: swipe.next != null),
      ],
    );
  }
}

Future<void> openFullScreenPlayer(BuildContext context) => Navigator.of(context).push(
  PageRouteBuilder(
    settings: const RouteSettings(name: FullScreenPlayer.route),
    opaque: true,
    transitionDuration: const Duration(milliseconds: 260),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (_, _, _) => const FullScreenPlayer(),
    transitionsBuilder: (_, a, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
      child: child,
    ),
  ),
);

/// Edge to edge: the cover fills the screen behind big controls, system bars
/// hidden and the screen kept on. Swipe the cover to switch, swipe down to leave.
class FullScreenPlayer extends StatefulWidget {
  const FullScreenPlayer({super.key});

  static const route = 'player/full';

  @override
  State<FullScreenPlayer> createState() => _FullScreenPlayerState();
}

class _FullScreenPlayerState extends State<FullScreenPlayer> {
  bool _wasAwake = false;
  double _pull = 0;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WakelockPlus.enabled.then((v) {
      _wasAwake = v;
      if (mounted) WakelockPlus.enable();
    }).ignore();
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (!_wasAwake) WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    const ink = Colors.white;
    final muted = Colors.white.withValues(alpha: .65);
    return Scaffold(
      backgroundColor: Colors.black,
      body: ListenableBuilder(
        listenable: Listenable.merge([Player.i, Podcasts.i]),
        builder: (context, _) {
          final pl = Player.i;
          final b = pl.book;
          if (b == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) Navigator.of(context).maybePop();
            });
            return const SizedBox.shrink();
          }
          final size = MediaQuery.of(context).size;
          final landscape = size.width > size.height;
          final art = math.min(landscape ? size.height * .62 : math.min(size.width - 56, size.height * .42), landscape ? 420.0 : 520.0);
          final track = pl.current;
          final kind = switch (b.source) {
            'podcast' => 'Podcast',
            'radio' => 'Live radio',
            _ => b.tracks.length > 1 ? 'Chapter ${b.trackIndex + 1} of ${b.tracks.length}' : 'Audiobook',
          };
          final cover = SizedBox(
            width: art,
            child: SwipeCover(
              key: ValueKey('full-${b.id}'),
              book: b,
              // A tap anywhere on the cover plays or pauses: a big target from across the room.
              onTap: () {
                haptic(true);
                pl.toggle();
              },
              child: AudioCover(b, radius: t.zen ? 22 : t.radius + 6),
            ),
          );
          final info = Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Label(kind, color: muted),
              const SizedBox(height: 10),
              SourceTitle(book: b, onTap: openSourceAction(context, b), color: ink, muted: muted, titleSize: landscape ? 22 : 26),
              if (b.tracks.length > 1 && track != null && track.title != b.title)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    track.title,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: muted),
                  ),
                ),
              const SizedBox(height: 22),
              PlayerScrubber(color: ink, muted: muted),
              const SizedBox(height: 14),
              PlayerControls(color: ink, disabled: Colors.white.withValues(alpha: .2), scale: landscape ? 1 : 1.12),
              if (pl.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    pl.error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFFF6B6B)),
                  ),
                ),
            ],
          );
          return GestureDetector(
            // Pull down to leave.
            onVerticalDragUpdate: (d) => setState(() => _pull = math.max(0, _pull + d.delta.dy)),
            onVerticalDragEnd: (d) {
              if (_pull > 120 || d.velocity.pixelsPerSecond.dy > 700) {
                Navigator.of(context).maybePop();
              } else {
                setState(() => _pull = 0);
              }
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                // The cover, blown up and blurred, as the backdrop.
                ClipRect(
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 50, sigmaY: 50, tileMode: TileMode.clamp),
                    child: Transform.scale(
                      scale: 1.4,
                      child: FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(width: 300, height: 300, child: AudioCover(b, shadow: false, radius: 0)),
                      ),
                    ),
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black.withValues(alpha: .35), Colors.black.withValues(alpha: .55), Colors.black.withValues(alpha: .85)]),
                  ),
                ),
                Transform.translate(
                  offset: Offset(0, _pull * .5),
                  child: Opacity(
                    opacity: (1 - _pull / 400).clamp(.4, 1.0),
                    child: SafeArea(
                      child: Column(
                        children: [
                          Row(
                            children: [
                              IconButton(
                                tooltip: 'Exit full screen',
                                onPressed: () => Navigator.of(context).maybePop(),
                                icon: const Icon(Icons.keyboard_arrow_down_sharp, size: 30, color: ink),
                              ),
                              const Spacer(),
                              IconButton(
                                tooltip: 'Exit full screen',
                                onPressed: () => Navigator.of(context).maybePop(),
                                icon: const Icon(Icons.fullscreen_exit_sharp, color: ink),
                              ),
                            ],
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 28),
                              child: landscape
                                  ? Row(
                                      children: [
                                        Expanded(child: Center(child: cover)),
                                        const SizedBox(width: 32),
                                        Expanded(
                                          child: Center(child: SingleChildScrollView(child: info)),
                                        ),
                                      ],
                                    )
                                  : Column(children: [const Spacer(), cover, const SizedBox(height: 32), info, const Spacer(flex: 2)]),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
