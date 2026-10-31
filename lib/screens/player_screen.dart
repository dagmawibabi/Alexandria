import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../core/net_image.dart';
import '../core/search_box.dart';
import '../core/settings.dart';
import '../core/theme.dart';
import '../core/ui.dart';
import '../models/audiobook.dart';
import '../models/book.dart';
import '../models/podcast.dart';
import '../models/radio.dart';
import '../services/audio.dart';
import '../services/downloads.dart';
import '../services/library.dart';
import '../services/podcasts.dart';
import '../services/radio.dart';
import '../services/read_aloud.dart';
import 'marks.dart';
import 'media_card.dart';
import 'meta_search.dart';
import 'podcasts_view.dart';
import 'radio_view.dart';
import 'reader/reader_screen.dart';

String fmtClock(Duration d) {
  final s = d.inSeconds.abs();
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
  return h > 0 ? '$h:${pad(m)}:${pad(sec)}' : '$m:${pad(sec)}';
}

/// Plays [b] and opens the full player.
Future<void> playAudiobook(BuildContext context, Audiobook b, {int? track}) async {
  Player.i.open(b, track: track);
  await Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const PlayerScreen()));
}

/// Plays [e] and opens the full player if that's set. On the episode already loaded, this only pauses or resumes.
Future<void> playEpisode(BuildContext context, Episode e) async {
  final starting = !Podcasts.i.isCurrent(e);
  // Playing takes it out of the queue, and the row calling this may go with it.
  final nav = Navigator.of(context);
  Podcasts.i.play(e);
  if (starting && Settings.i.openPlayerOnPlay) await nav.push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const PlayerScreen()));
}

/// Plays [s] and opens the full player if that's set. On the station already loaded, this only pauses or resumes.
Future<void> playStation(BuildContext context, Station s) async {
  final starting = !RadioDirectory.i.isCurrent(s.id);
  final nav = Navigator.of(context);
  RadioDirectory.i.play(s);
  if (starting && Settings.i.openPlayerOnPlay) await nav.push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const PlayerScreen()));
}

/// An audiobook's cover: saved file, then catalogue URL, then a generated one.
class AudioCover extends StatelessWidget {
  const AudioCover(this.book, {super.key, this.radius, this.shadow = true, this.showProgress = false});
  final Audiobook book;
  final double? radius;
  final bool shadow;
  final bool showProgress;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final fallback = GeneratedCover(Book(id: book.id, title: book.title, author: book.author, format: BookFormat.epub, path: ''));
    final path = book.coverPath;
    final Widget img = path != null && File(path).existsSync()
        ? monoImage(Image.file(File(path), fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, _, _) => fallback))
        : (book.coverUrl != null ? NetImage(book.coverUrl!, fallback: fallback) : fallback);
    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius ?? (t.zen ? 14 : t.radius + 2)),
          border: t.zen ? null : Border.all(color: t.line),
          boxShadow: shadow ? [BoxShadow(color: Colors.black.withValues(alpha: t.dark ? .5 : .14), blurRadius: 20, offset: const Offset(0, 8))] : null,
        ),
        child: Stack(fit: StackFit.expand, children: [
          img,
          if (showProgress && book.progress > 0)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 3,
              child: FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: book.progress, child: Container(color: t.accent)),
            ),
        ]),
      ),
    );
  }
}

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Player.i,
          builder: (context, _) {
            final pl = Player.i;
            final b = pl.book;
            if (b == null) return const Center(child: Label('Nothing playing'));
            final track = pl.current;
            final dur = pl.duration > Duration.zero ? pl.duration : Duration(milliseconds: track?.ms ?? 0);
            final pos = _drag != null ? Duration(milliseconds: (_drag! * dur.inMilliseconds).round()) : pl.position;
            final frac = dur.inMilliseconds == 0 ? 0.0 : (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0);
            final left = b.timed ? Duration(milliseconds: ((b.totalMs - b.elapsedMs) / b.speed).round()) : null;
            final w = MediaQuery.of(context).size.width;

            final podcast = b.source == 'podcast';
            final live = b.source == 'radio';
            final station = live ? RadioDirectory.i.stationFor(b.sourceKey) : null;
            final episode = podcast ? Podcasts.i.episodeFor(b) : null;
            final text = podcast || live ? null : AudioLibrary.i.bookFor(b);
            return ListView(padding: const EdgeInsets.fromLTRB(24, 4, 24, 32), children: [
              Row(children: [
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.keyboard_arrow_down_sharp, size: 28)),
                Expanded(child: Center(child: Label(live ? 'Live radio' : podcast ? 'Podcast' : (b.streaming ? 'Streaming · ${_sourceName(b)}' : (b.offline ? 'Downloaded' : 'Now playing'))))),
                IconButton(
                  onPressed: () {
                    if (station != null) {
                      showStationMenu(context, station);
                    } else if (episode != null) {
                      showEpisode(context, episode);
                    } else {
                      showAudiobookActions(context, b, fromPlayer: true);
                    }
                  },
                  icon: const Icon(Icons.more_horiz_sharp),
                ),
              ]),
              const SizedBox(height: 12),
              Center(child: SizedBox(width: math.min(w * .7, 320), child: Hero(tag: 'audio-${b.id}', child: AudioCover(b)))),
              const SizedBox(height: 26),
              Text(b.title, textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, height: 1.15, letterSpacing: -.3)),
              if (b.author.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(b.author, textAlign: TextAlign.center, style: TextStyle(color: t.muted, fontSize: 15))),
              const SizedBox(height: 14),
              if (b.tracks.length > 1)
                GestureDetector(
                  onTap: () => _chapters(context),
                  child: Column(children: [
                    Label('Chapter ${b.trackIndex + 1} of ${b.tracks.length}', color: t.accent),
                    const SizedBox(height: 3),
                    Text(track?.title ?? '', textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.ink.withValues(alpha: .8))),
                  ]),
                )
              else if (episode?.published != null)
                Center(child: Label(fmtDate(episode!.published), color: t.accent)),
              const SizedBox(height: 18),
              if (live)
                Center(
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 8, height: 8, decoration: BoxDecoration(color: pl.playing ? t.accent : t.muted, shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    Label(pl.loading ? 'Connecting' : (pl.playing ? 'Live' : 'Paused'), color: t.ink, weight: FontWeight.w600),
                  ]),
                )
              else ...[
              Slider(
                value: frac,
                onChanged: dur == Duration.zero ? null : (v) => setState(() => _drag = v),
                onChangeEnd: (v) {
                  pl.seek(Duration(milliseconds: (v * dur.inMilliseconds).round()));
                  setState(() => _drag = null);
                },
              ),
              Row(children: [
                Label(fmtClock(pos), color: t.ink),
                const Spacer(),
                Label(dur == Duration.zero ? '--:--' : '-${fmtClock(dur - pos)}'),
              ]),
              ],
              const SizedBox(height: 18),
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                if (!live) _round(context, Icons.skip_previous_sharp, pl.previous, size: 46, enabled: b.tracks.length > 1 || pl.position.inSeconds > 3),
                if (!live) _round(context, Icons.replay_10_sharp, () => pl.skip(-10), size: 52),
                GestureDetector(
                  onTap: () {
                    haptic(true);
                    pl.toggle();
                  },
                  child: Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(color: t.accent, borderRadius: BorderRadius.circular(t.zen ? 22 : t.radius + 6), boxShadow: [BoxShadow(color: t.accent.withValues(alpha: .3), blurRadius: 18, offset: const Offset(0, 6))]),
                    child: pl.loading
                        ? Padding(padding: const EdgeInsets.all(26), child: CircularProgressIndicator(strokeWidth: 2, color: t.onAccent))
                        : Icon(pl.playing ? Icons.pause_sharp : Icons.play_arrow_sharp, size: 38, color: t.onAccent),
                  ),
                ),
                if (!live) _round(context, Icons.forward_30_sharp, () => pl.skip(30), size: 52),
                if (!live) podcast
                    ? _round(context, Icons.skip_next_sharp, () => Podcasts.i.queue.isEmpty ? null : Podcasts.i.play(Podcasts.i.queue.first), size: 46, enabled: Podcasts.i.queue.isNotEmpty)
                    : _round(context, Icons.skip_next_sharp, pl.next, size: 46, enabled: b.trackIndex < b.tracks.length - 1),
              ]),
              if (pl.error != null) Padding(padding: const EdgeInsets.only(top: 14), child: Text(pl.error!, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFE5243B)))),
              const SizedBox(height: 22),
              Row(children: [
                if (!live) ...[
                  Expanded(child: _chip(context, Icons.speed_sharp, '${_speedLabel(b.speed)}×', () => _speed(context))),
                  const SizedBox(width: 8),
                ],
                Expanded(child: _chip(context, Icons.bedtime_outlined, _sleepLabel(pl), () => _sleepSheet(context), on: pl.sleepAt != null || pl.sleepAtTrackEnd)),
                if (!live) const SizedBox(width: 8),
                if (!live) Expanded(
                  child: podcast
                      ? _chip(context, Icons.queue_music_sharp, Podcasts.i.queue.isEmpty ? 'Queue' : 'Up next ${Podcasts.i.queue.length}', () => showQueue(context))
                      : _chip(context, Icons.format_list_bulleted_sharp, 'Chapters', () => _chapters(context)),
                ),
              ]),
              if (text != null) ...[
                const SizedBox(height: 8),
                _chip(context, Icons.menu_book_sharp, 'Read along', () => readAlong(context, b, text)),
              ],
              const SizedBox(height: 12),
              MarksBar(
                mark: station != null ? RadioDirectory.i.markOf(station.id) : (episode != null ? Podcasts.i.episodeMark(episode) : b.mark),
                title: b.title,
                changed: () {
                  if (station != null) {
                    RadioDirectory.i.changed(station);
                  } else if (episode != null) {
                    Podcasts.i.marksChanged();
                  } else {
                    AudioLibrary.i.touch(b);
                  }
                },
                here: live ? null : () => (track: b.trackIndex, ms: pl.position.inMilliseconds),
                onSeek: live ? null : (n) => pl.goTo(n.track, n.ms),
                folders: station != null ? () => RadioDirectory.i.foldersOf(station.id) : (episode != null ? null : () => b.folderIds),
                onFolder: station != null ? (id) => RadioDirectory.i.toggleFolder(station, id) : (episode != null ? null : (id) => AudioLibrary.i.toggleFolder(b, id)),
              ),
              if (!podcast && !live) ...[
                const SizedBox(height: 16),
                ClipRRect(borderRadius: BorderRadius.circular(2), child: LinearProgressIndicator(value: b.progress, minHeight: 3)),
                const SizedBox(height: 8),
                Row(children: [
                  Label('${(b.progress * 100).round()}% of book'),
                  const Spacer(),
                  if (left != null) Label('${fmtDuration(left.inSeconds)} left'),
                ]),
              ],
              if (b.description.isNotEmpty) ...[
                SectionHeader('', podcast ? 'Show notes' : 'About', padding: const EdgeInsets.fromLTRB(0, 28, 0, 10)),
                CollapsibleText(b.description, lines: 4, style: TextStyle(height: 1.5, color: t.ink.withValues(alpha: .85))),
              ],
            ]);
          },
        ),
      ),
    );
  }

  static String _sourceName(Audiobook b) => b.source == 'librivox' ? 'LibriVox' : (b.source == 'archive' ? 'Internet Archive' : 'web');

  static String _speedLabel(double v) => v == v.roundToDouble() ? v.toStringAsFixed(1) : v.toString();

  static String _sleepLabel(Player pl) {
    if (pl.sleepAtTrackEnd) return 'End of ch.';
    final at = pl.sleepAt;
    if (at == null) return 'Sleep';
    final left = at.difference(DateTime.now());
    return left.inMinutes >= 1 ? '${left.inMinutes + 1}m' : '${left.inSeconds}s';
  }

  Widget _round(BuildContext context, IconData i, VoidCallback onTap, {double size = 48, bool enabled = true}) {
    final t = Tokens.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled
          ? () {
              haptic();
              onTap();
            }
          : null,
      child: SizedBox(width: size, height: size, child: Icon(i, size: size * .55, color: enabled ? t.ink : t.line)),
    );
  }

  Widget _chip(BuildContext context, IconData i, String label, VoidCallback onTap, {bool on = false}) {
    final t = Tokens.of(context);
    return GestureDetector(
      onTap: () {
        haptic();
        onTap();
      },
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: on ? t.accent.withValues(alpha: .15) : t.raised,
          borderRadius: BorderRadius.circular(t.zen ? 12 : t.radius),
          border: t.zen ? null : Border.all(color: on ? t.accent : t.line),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(i, size: 17, color: on ? t.accent : t.ink),
          const SizedBox(width: 6),
          Flexible(child: Label(label, color: on ? t.accent : t.ink, weight: FontWeight.w600)),
        ]),
      ),
    );
  }

  void _speed(BuildContext context) {
    showSheet(context, builder: (ctx) {
      final t = Tokens.of(ctx);
      return ListenableBuilder(
        listenable: Player.i,
        builder: (ctx, _) {
          final cur = Player.i.book?.speed ?? 1;
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Label('Playback speed', color: t.accent),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final v in const [.75, .9, 1.0, 1.1, 1.25, 1.5, 1.75, 2.0]) Tag('${_speedLabel(v)}×', filled: (cur - v).abs() < .01, onTap: () => Player.i.setSpeed(v)),
              ]),
              const SizedBox(height: 8),
              SliderRow(label: 'Fine', value: cur, min: .5, max: 3, divisions: 50, format: (v) => '${v.toStringAsFixed(2)}×', onChanged: (v) => Player.i.setSpeed((v * 20).round() / 20)),
            ]),
          );
        },
      );
    });
  }

  void _sleepSheet(BuildContext context) {
    showSheet(context, builder: (ctx) {
      final t = Tokens.of(ctx);
      Widget opt(String l, VoidCallback f) => ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(l, style: TextStyle(color: t.ink, fontWeight: FontWeight.w500)),
            onTap: () {
              haptic();
              f();
              Navigator.pop(ctx);
            },
          );
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Label('Sleep timer', color: t.accent),
          const SizedBox(height: 6),
          for (final m in const [5, 15, 30, 45, 60, 90]) opt('$m minutes', () => Player.i.setSleep(Duration(minutes: m))),
          if (Player.i.book?.source != 'radio') opt('End of this chapter', () => Player.i.setSleep(null, trackEnd: true)),
          if (Player.i.sleepAt != null || Player.i.sleepAtTrackEnd) opt('Turn off', () => Player.i.setSleep(null)),
        ]),
      );
    });
  }

  void _chapters(BuildContext context) {
    showSheet(context, scroll: false, builder: (ctx) {
      final t = Tokens.of(ctx);
      final b = Player.i.book;
      if (b == null) return const SizedBox.shrink();
      return ListenableBuilder(
        listenable: Listenable.merge([Player.i, Downloads.i, AudioLibrary.i]),
        builder: (ctx, _) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.fromLTRB(20, 4, 20, 8), child: Label('Chapters · ${b.tracks.length}', color: t.accent)),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 20),
              itemCount: b.tracks.length,
              itemBuilder: (_, i) {
                final tr = b.tracks[i];
                final on = i == b.trackIndex;
                return InkWell(
                  onTap: () {
                    haptic();
                    Player.i.jumpTo(i);
                    Navigator.pop(ctx);
                  },
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(20, 6, 8, 6),
                    decoration: BoxDecoration(border: Border(left: BorderSide(color: on ? t.accent : Colors.transparent, width: 3))),
                    child: Row(children: [
                      SizedBox(width: 34, child: Label(pad(i + 1), color: on ? t.accent : t.muted)),
                      Expanded(child: Text(tr.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.ink, fontWeight: on ? FontWeight.w700 : FontWeight.w500))),
                      if (on && Player.i.playing) Padding(padding: const EdgeInsets.only(right: 8), child: Icon(Icons.graphic_eq_sharp, size: 16, color: t.accent)),
                      if (tr.ms > 0) Label(fmtClock(Duration(milliseconds: tr.ms))),
                      ChapterDownload(book: b, index: i),
                    ]),
                  ),
                );
              },
            ),
          ),
        ]),
      );
    });
  }
}

/// Download, cancel or remove one chapter. Nothing for a book made from your own files.
class ChapterDownload extends StatelessWidget {
  const ChapterDownload({super.key, required this.book, required this.index});
  final Audiobook book;
  final int index;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final tr = book.tracks[index];
    if (!tr.remote && !tr.downloaded) return const SizedBox(width: 8);
    final key = AudioLibrary.trackKey(book, index);
    final p = Downloads.i.progress[key];
    if (p != null) {
      return IconButton(
        tooltip: 'Cancel download',
        onPressed: () => Downloads.i.cancel(key),
        icon: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, value: p < 0 ? null : p)),
      );
    }
    if (tr.downloaded) {
      return IconButton(
        tooltip: 'Remove download',
        onPressed: () {
          // The file can't go while it's the one playing.
          if (Player.i.book?.id == book.id && book.trackIndex == index && Player.i.playing) return toast(context, 'Pause this chapter first');
          AudioLibrary.i.removeTrackDownload(book, index);
        },
        icon: Icon(Icons.download_done_sharp, size: 20, color: t.accent),
      );
    }
    final busy = Downloads.i.running(book.id);
    return IconButton(
      tooltip: 'Download chapter',
      onPressed: busy
          ? null
          : () async {
              final ok = await AudioLibrary.i.downloadTrack(book, index);
              if (!ok && !Downloads.i.cancelled(key) && context.mounted) toast(context, 'Download stopped. Tap again to resume.');
            },
      icon: Icon(Icons.download_sharp, size: 20, color: busy ? t.line : t.muted),
    );
  }
}

/// Edit, re-identify or remove an audiobook.
Future<void> showAudiobookActions(BuildContext context, Audiobook b, {bool fromPlayer = false}) {
  return showSheet(context, builder: (ctx) {
    final t = Tokens.of(ctx);
    Widget row(IconData i, String l, VoidCallback onTap, {Color? color}) => ListTile(
          dense: true,
          leading: Icon(i, size: 20, color: color ?? t.ink),
          title: Text(l, style: TextStyle(color: color ?? t.ink, fontWeight: FontWeight.w500)),
          onTap: () {
            haptic();
            onTap();
          },
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Row(children: [
            SizedBox(width: 48, child: AudioCover(b, shadow: false)),
            const SizedBox(width: 14),
            Expanded(child: Text(b.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
          ]),
        ),
        // Rate, favourite and take notes right from the menu.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: ListenableBuilder(
            listenable: AudioLibrary.i,
            builder: (_, _) => MarksBar(
              mark: b.mark,
              title: b.title,
              changed: () => AudioLibrary.i.touch(b),
              here: () => (track: b.trackIndex, ms: b.positionMs),
              folders: () => b.folderIds,
              onFolder: (id) => AudioLibrary.i.toggleFolder(b, id),
            ),
          ),
        ),
        ListenableBuilder(
          listenable: Downloads.i,
          builder: (ctx, _) {
            final p = Downloads.i.progress[b.id];
            if (p != null) {
              return row(Icons.close_sharp, 'Downloading ${(p * 100).round()}% · tap to cancel', () => Downloads.i.cancel(b.id));
            }
            if (b.downloadable) {
              return row(Icons.download_sharp, 'Download for offline', () async {
                final ok = await AudioLibrary.i.download(b);
                if (context.mounted) toast(context, ok ? 'Downloaded' : (Downloads.i.cancelled(b.id) ? 'Download cancelled' : 'Download stopped. Try again to resume.'));
              });
            }
            if (b.offline) return row(Icons.cloud_off_sharp, 'Remove download (stream again)', () => AudioLibrary.i.removeDownload(b));
            return const SizedBox.shrink();
          },
        ),
        row(Icons.menu_book_outlined, AudioLibrary.i.bookFor(b) == null ? 'Attach the book' : 'Change attached book', () async {
          Navigator.pop(ctx);
          final book = await pickBookForAudio(context, audio: b);
          if (book != null) AudioLibrary.i.linkBook(b, book);
        }),
        if (AudioLibrary.i.bookFor(b) != null)
          row(Icons.link_off_sharp, 'Detach the book', () {
            AudioLibrary.i.linkBook(b, null);
            Navigator.pop(ctx);
          }),
        row(Icons.ios_share_sharp, 'Share card', () {
          Navigator.pop(ctx);
          showMediaCard(context, ShareItem.audiobook(b));
        }),
        if (b.tracks.length > 1)
          row(Icons.ios_share_outlined, 'Share card for chapter ${b.trackIndex + 1}', () {
            Navigator.pop(ctx);
            showMediaCard(context, ShareItem.chapter(b, b.trackIndex));
          }),
        row(Icons.search_sharp, 'Find info online', () async {
          Navigator.pop(ctx);
          final info = await showMetadataSearch(context, query: b.title, author: b.author);
          if (info != null) {
            await AudioLibrary.i.applyInfo(b, info);
            if (context.mounted) toast(context, 'Info updated');
          }
        }),
        row(Icons.edit_outlined, 'Edit details', () {
          Navigator.pop(ctx);
          editAudiobook(context, b);
        }),
        row(Icons.image_outlined, 'Choose cover image', () async {
          Navigator.pop(ctx);
          final files = await FilePicker.pickFiles(type: FileType.image);
          final path = files.firstOrNull?.path;
          if (path != null) await AudioLibrary.i.setCover(b, path);
        }),
        row(b.finished ? Icons.replay_sharp : Icons.check_sharp, b.finished ? 'Mark as not finished' : 'Mark as finished', () {
          b.finished = !b.finished;
          b.finishedAt = b.finished ? DateTime.now() : null;
          AudioLibrary.i.touch(b);
          Navigator.pop(ctx);
        }),
        row(Icons.delete_outline_sharp, 'Remove from shelf', color: const Color(0xFFE5243B), () async {
          final ok = await confirm(ctx, 'Remove audiobook', b.source == 'local' ? 'Deletes "${b.title}" and its copied audio files from Alexandria.' : 'Removes "${b.title}" from your shelf.');
          if (!ok) return;
          await AudioLibrary.i.remove(b);
          if (ctx.mounted) Navigator.pop(ctx);
          if (fromPlayer && context.mounted) Navigator.of(context).maybePop();
        }),
      ]),
    );
  });
}

Future<void> editAudiobook(BuildContext context, Audiobook b) {
  final title = TextEditingController(text: b.title);
  final author = TextEditingController(text: b.author);
  final narrator = TextEditingController(text: b.narrator);
  final desc = TextEditingController(text: b.description);
  return showSheet(context, builder: (ctx) {
    Widget field(TextEditingController c, String l, {int lines = 1}) =>
        Padding(padding: const EdgeInsets.only(bottom: 8), child: TextField(controller: c, maxLines: lines, decoration: InputDecoration(labelText: l)));
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Label('Edit audiobook'),
        const SizedBox(height: 12),
        field(title, 'Title'),
        field(author, 'Author'),
        field(narrator, 'Narrator'),
        field(desc, 'Description', lines: 5),
        const SizedBox(height: 8),
        PrimaryButton('Save', expand: true, onTap: () {
          b
            ..title = title.text.trim().isEmpty ? b.title : title.text.trim()
            ..author = author.text.trim()
            ..narrator = narrator.text.trim()
            ..description = desc.text.trim();
          AudioLibrary.i.touch(b);
          Navigator.pop(ctx);
        }),
      ]),
    );
  });
}

/// Opens the attached ebook in follow mode: the page keeps up with the narration.
Future<void> readAlong(BuildContext context, Audiobook b, Book book) async {
  if (Player.i.book?.id != b.id) Player.i.open(b);
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReaderScreen(book: book, follow: b)));
}

/// Chooses the ebook an audiobook narrates: from the library, a new file,
/// or (with [audio]) a free Project Gutenberg text.
Future<Book?> pickBookForAudio(BuildContext context, {Audiobook? audio, String query = ''}) {
  return showSheet<Book>(context, scroll: false, builder: (ctx) => _BookPicker(audio: audio, query: query));
}

class _BookPicker extends StatefulWidget {
  const _BookPicker({this.audio, this.query = ''});
  final Audiobook? audio;
  final String query;

  @override
  State<_BookPicker> createState() => _BookPickerState();
}

class _BookPickerState extends State<_BookPicker> {
  late final _q = TextEditingController(text: widget.query.isNotEmpty ? widget.query : (widget.audio?.title ?? ''));
  bool _busy = false;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'epub', 'docx']);
    final f = files.firstOrNull;
    if (f?.path == null) return;
    setState(() => _busy = true);
    try {
      final book = await Library.i.importFile(f!.path!, displayName: f.name);
      if (mounted) Navigator.pop(context, book);
    } catch (e) {
      if (mounted) toast(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _gutenberg() async {
    final a = widget.audio;
    if (a == null) return;
    setState(() => _busy = true);
    final book = await AudioLibrary.i.attachFreeText(a);
    if (!mounted) return;
    setState(() => _busy = false);
    if (book == null) return toast(context, 'No free text found for this title');
    Navigator.pop(context, book);
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final q = _q.text.toLowerCase().split(RegExp(r'\s+')).where((w) => w.length > 2).toList();
    final books = [...Library.i.books]..sort((a, b) {
        int score(Book x) => q.where((w) => '${x.title} ${x.author}'.toLowerCase().contains(w)).length;
        return score(b).compareTo(score(a));
      });
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Label('Attach the book', color: t.accent),
        const SizedBox(height: 6),
        Text('Read the text while it\'s narrated. The page follows along.', style: TextStyle(color: t.muted, fontSize: 13)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: PrimaryButton('Import file', ghost: true, icon: Icons.file_open_outlined, onTap: _busy ? null : _import)),
          if (widget.audio != null) ...[
            const SizedBox(width: 8),
            Expanded(child: PrimaryButton('Free text', ghost: true, icon: Icons.public_sharp, onTap: _busy ? null : _gutenberg)),
          ],
        ]),
        if (_busy) const Padding(padding: EdgeInsets.only(top: 10), child: LinearProgressIndicator()),
        const SizedBox(height: 14),
        SearchBox(historyKey: 'attach-book', controller: _q, onChanged: (_) => setState(() {}), decoration: const InputDecoration(hintText: 'Search your library', prefixIcon: Icon(Icons.search_sharp, size: 18))),
        const SizedBox(height: 6),
        Flexible(
          child: books.isEmpty
              ? Padding(padding: const EdgeInsets.all(20), child: Text('Your library is empty.', style: TextStyle(color: t.muted)))
              : ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: books.length,
                  itemBuilder: (_, i) {
                    final b = books[i];
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => Navigator.pop(context, b),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(children: [
                          SizedBox(width: 40, child: Cover(b)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(b.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                              if (b.author.isNotEmpty) Text(b.author, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.muted, fontSize: 12.5)),
                            ]),
                          ),
                          Label(b.formatLabel, size: 9),
                        ]),
                      ),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

/// [MiniPlayer] for a page outside the tabs, with no tab bar to keep it off the screen's edge.
class PagePlayer extends StatelessWidget {
  const PagePlayer({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([Player.i, ReadAloud.i]),
      builder: (context, _) => Player.i.book == null && !ReadAloud.i.active ? const SizedBox.shrink() : const SafeArea(top: false, child: MiniPlayer()),
    );
  }
}

/// The bar above the tabs while a book is loaded.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  /// A book being read aloud, while you're away from the reader.
  Widget _readAloud(BuildContext context) {
    final t = Tokens.of(context);
    final r = ReadAloud.i;
    final b = r.book!;
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReaderScreen(book: b))),
      child: Container(
        margin: t.zen ? const EdgeInsets.fromLTRB(10, 0, 10, 8) : EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        decoration: t.zen
            ? BoxDecoration(color: t.surface, borderRadius: BorderRadius.circular(18), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .12), blurRadius: 18, offset: const Offset(0, 4))])
            : BoxDecoration(color: t.surface, border: Border(top: BorderSide(color: t.line))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          LinearProgressIndicator(value: r.fraction.clamp(0.0, 1.0), minHeight: 2, backgroundColor: Colors.transparent),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
            child: Row(children: [
              SizedBox(width: 30, child: Cover(b)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(b.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  Text(r.chapter.isNotEmpty ? r.chapter : 'Reading aloud', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.muted, fontSize: 12)),
                ]),
              ),
              IconButton(tooltip: 'Previous paragraph', onPressed: r.previous, icon: const Icon(Icons.skip_previous_sharp)),
              IconButton(onPressed: r.toggle, icon: Icon(r.playing ? Icons.pause_sharp : Icons.play_arrow_sharp, size: 28, color: t.accent)),
              IconButton(tooltip: 'Stop', onPressed: r.stop, icon: Icon(Icons.close_sharp, size: 20, color: t.muted)),
            ]),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([Player.i, ReadAloud.i]),
      builder: (context, _) {
        if (ReadAloud.i.active) return _readAloud(context);
        final pl = Player.i;
        final b = pl.book;
        if (b == null) return const SizedBox.shrink();
        final dur = pl.duration.inMilliseconds;
        return GestureDetector(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const PlayerScreen())),
          child: Container(
            margin: t.zen ? const EdgeInsets.fromLTRB(10, 0, 10, 8) : EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            decoration: t.zen
                ? BoxDecoration(color: t.surface, borderRadius: BorderRadius.circular(18), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .12), blurRadius: 18, offset: const Offset(0, 4))])
                : BoxDecoration(color: t.surface, border: Border(top: BorderSide(color: t.line))),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              LinearProgressIndicator(value: dur == 0 ? 0 : (pl.position.inMilliseconds / dur).clamp(0.0, 1.0), minHeight: 2, backgroundColor: Colors.transparent),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
                child: Row(children: [
                  SizedBox(width: 42, child: AudioCover(b, shadow: false, radius: 8)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text(b.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      Text(pl.error ?? pl.current?.title ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.muted, fontSize: 12)),
                    ]),
                  ),
                  if (b.source != 'radio') IconButton(onPressed: () => pl.skip(-10), icon: const Icon(Icons.replay_10_sharp)),
                  IconButton(
                    onPressed: pl.toggle,
                    icon: pl.loading
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(pl.playing ? Icons.pause_sharp : Icons.play_arrow_sharp, size: 28, color: t.accent),
                  ),
                  IconButton(onPressed: pl.close, icon: Icon(Icons.close_sharp, size: 20, color: t.muted)),
                ]),
              ),
            ]),
          ),
        );
      },
    );
  }
}
