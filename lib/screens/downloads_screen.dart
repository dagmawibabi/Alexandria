import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../core/theme.dart';
import '../core/ui.dart';
import '../models/audiobook.dart';
import '../services/audio.dart';
import '../services/downloads.dart';
import '../services/podcasts.dart';
import 'audiobook_screen.dart';
import 'player_screen.dart';
import 'podcasts_view.dart';

void openDownloads(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EpisodeDownloadsScreen()));
}

String _size(int bytes) {
  if (bytes >= 1 << 30) return '${(bytes / (1 << 30)).toStringAsFixed(1)} GB';
  return '${(bytes / (1 << 20)).toStringAsFixed(bytes >= 100 << 20 ? 0 : 1)} MB';
}

/// Sizes of finished downloads, which don't change: read from disk once, not
/// on every rebuild (the page rebuilds with each progress tick while downloading).
final _sizes = <String, int>{};

int _fileSize(String? path) {
  if (path == null) return 0;
  final known = _sizes[path];
  if (known != null) return known;
  final f = File(path);
  if (!f.existsSync()) return 0;
  return _sizes[path] = f.lengthSync();
}

String _mb(int bytes) => bytes >= 1 << 30 ? '${(bytes / (1 << 30)).toStringAsFixed(2)} GB' : '${(bytes / (1 << 20)).toStringAsFixed(1)} MB';

String _left(Duration d) {
  final s = d.inSeconds;
  if (s < 60) return '${s}s left';
  if (s < 3600) return '${(s / 60).ceil()} min left';
  return '${s ~/ 3600} h ${(s % 3600 / 60).round()} min left';
}

/// What's still arriving, for the jobs [mine] picks out.
class _Active extends StatelessWidget {
  const _Active({required this.mine});
  final bool Function(String key) mine;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final active = Downloads.i.progress.entries.where((e) => mine(e.key)).toList();
    if (active.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionHeader('', active.length == 1 ? 'Downloading' : 'Downloading · ${active.length}', padding: const EdgeInsets.fromLTRB(0, 18, 0, 8)),
      for (final e in active) Padding(padding: const EdgeInsets.only(bottom: 8), child: _ActiveRow(jobKey: e.key, value: e.value)),
      Text('Keeps going in the background, and picks up where it stopped if the connection drops.', style: TextStyle(color: t.muted, fontSize: 12.5)),
      const SizedBox(height: 10),
    ]);
  }
}

/// One download in progress: its art, what it is, and how it's going.
class _ActiveRow extends StatelessWidget {
  const _ActiveRow({required this.jobKey, required this.value});
  final String jobKey;
  final double value;

  /// What a job key stands for: a show's "download all", an episode, or an
  /// audiobook (whole, or one chapter as "id#n").
  ({Widget art, String title, String? sub, VoidCallback? open}) _what(BuildContext context) {
    final key = jobKey;
    final label = Downloads.i.labels[key];
    if (key.startsWith('show:')) {
      final pod = Podcasts.i.cached(key.substring(5));
      final title = pod?.title ?? label ?? 'Episodes';
      return (art: PodcastArt(pod?.imageUrl, title: title), title: title, sub: label?.split(': ').last ?? 'All episodes', open: pod == null ? null : () => openPodcast(context, feedUrl: pod.feedUrl));
    }
    final ep = Podcasts.i.states[key]?.episode;
    if (ep != null) return (art: PodcastArt(ep.art, title: ep.podcastTitle), title: ep.title, sub: ep.podcastTitle, open: () => showEpisode(context, ep));
    final parts = key.split('#');
    final book = AudioLibrary.i.byId(parts.first);
    if (book != null) {
      final n = parts.length > 1 ? int.tryParse(parts[1]) : null;
      final track = n != null && n < book.tracks.length ? book.tracks[n] : null;
      final sub = track != null ? 'Chapter ${n! + 1} · ${track.title}' : '${book.tracks.length} chapters${book.author.isEmpty ? '' : ' · ${book.author}'}';
      return (art: AudioCover(book, shadow: false), title: book.title, sub: sub, open: () => openAudiobook(context, book));
    }
    final t = Tokens.of(context);
    return (art: AspectRatio(aspectRatio: 1, child: Container(color: t.line, child: Icon(Icons.download_sharp, color: t.muted))), title: label ?? 'Downloading', sub: null, open: null);
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final w = _what(context);
    final st = Downloads.i.stats[jobKey];
    final pct = value >= 0 ? '${(value * 100).floor()}%' : null;
    final String status;
    if (st != null && st.attempt > 1 && st.rate == 0) {
      status = 'Connection dropped · retrying (try ${st.attempt} of 5)';
    } else if (st == null || st.got == 0) {
      status = pct != null && value > 0 ? pct : 'Starting…';
    } else {
      final left = st.left;
      status = [
        ?pct,
        st.total > 0 ? '${_mb(st.got)} of ${_mb(st.total)}' : _mb(st.got),
        if (st.rate > 0) '${_mb(st.rate.round())}/s',
        if (left != null) _left(left),
      ].join(' · ');
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: w.open,
      child: Panel(
        padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 56, child: w.art),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (w.sub != null) Label(w.sub!, size: 9, color: t.accent),
              if (w.sub != null) const SizedBox(height: 3),
              Text(w.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, height: 1.25)),
              const SizedBox(height: 8),
              ClipRRect(borderRadius: BorderRadius.circular(2), child: LinearProgressIndicator(value: value < 0 ? null : value, minHeight: 4)),
              const SizedBox(height: 6),
              Label(status, size: 9),
            ]),
          ),
          IconButton(tooltip: 'Cancel', onPressed: () => Downloads.i.cancel(jobKey), icon: Icon(Icons.close_sharp, color: t.muted)),
        ]),
      ),
    );
  }
}

Widget _empty(BuildContext context, String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Text(text, textAlign: TextAlign.center, style: TextStyle(color: Tokens.of(context).muted, height: 1.4)),
    );

/// Downloaded podcast episodes, playable without a connection.
class EpisodeDownloadsScreen extends StatelessWidget {
  const EpisodeDownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: AppTitle('Downloaded episodes')),
      bottomNavigationBar: const PagePlayer(),
      body: ListenableBuilder(
        // Not the player, which ticks several times a second: rows follow it themselves.
        listenable: Listenable.merge([Podcasts.i, Downloads.i]),
        builder: (context, _) {
          final episodes = Podcasts.i.downloaded.where((s) => _fileSize(s.localPath) > 0).toList();
          final used = episodes.fold(0, (a, s) => a + _fileSize(s.localPath));
          return ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 32), children: [
            Label('${episodes.length} episodes · ${_size(used)} · plays without internet', size: 9),
            _Active(mine: (k) => AudioLibrary.i.byId(k.split('#').first) == null),
            if (episodes.isEmpty) _empty(context, 'Tap an episode, then the download button, to keep it for offline.'),
            for (final s in episodes) EpisodeRow(episode: s.episode, showShow: true),
          ]);
        },
      ),
    );
  }
}

/// The Audiobooks tab's Downloads view: everything on your shelf that plays offline.
class AudiobookDownloads extends StatelessWidget {
  const AudiobookDownloads({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([Downloads.i, AudioLibrary.i]),
      builder: (context, _) {
        // Books made from your own files are always offline too.
        final books = AudioLibrary.i.recent.where((b) => b.tracks.any((t) => !t.remote)).toList();
        final used = books.fold(0, (a, b) => a + b.tracks.fold(0, (x, t) => x + (t.remote ? 0 : _fileSize(t.path))));
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Label('${books.length} audiobooks · ${_size(used)} · plays without internet', size: 9),
            _Active(mine: (k) => AudioLibrary.i.byId(k.split('#').first) != null),
            if (books.isEmpty) _empty(context, 'Download a free audiobook from its page, or from its menu on your shelf.'),
            for (final b in books) _BookRow(book: b),
          ]),
        );
      },
    );
  }
}

class _BookRow extends StatelessWidget {
  const _BookRow({required this.book});
  final Audiobook book;

  // Follows the player itself, so only this row redraws as it plays.
  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: Player.i, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final t = Tokens.of(context);
    final b = book;
    final saved = b.tracks.where((x) => !x.remote).length;
    final size = b.tracks.fold(0, (a, x) => a + (x.remote ? 0 : _fileSize(x.path)));
    final fromFiles = b.source == 'local';
    final active = Player.i.book?.id == b.id;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => openAudiobook(context, b),
      onLongPress: () => showAudiobookActions(context, b),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.line))),
        child: Row(children: [
          SizedBox(width: 56, child: AudioCover(b, shadow: false)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(b.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, color: active ? t.accent : t.ink)),
              const SizedBox(height: 3),
              Label([if (fromFiles) 'Your files' else if (saved < b.tracks.length) '$saved of ${b.tracks.length} chapters' else 'All chapters', _size(size)].join(' · '), size: 9),
            ]),
          ),
          if (!fromFiles)
            IconButton(
              tooltip: 'Remove download',
              onPressed: () async {
                if (await confirm(context, 'Remove download', 'Frees ${_size(size)}. "${b.title}" stays on your shelf and streams again.')) AudioLibrary.i.removeDownload(b);
              },
              icon: Icon(Icons.delete_outline_sharp, color: t.muted),
            ),
          ToolButton(active && Player.i.playing ? Icons.pause_sharp : Icons.play_arrow_sharp, size: 40, active: active, onTap: () => active ? Player.i.toggle() : Player.i.open(b)),
        ]),
      ),
    );
  }
}
