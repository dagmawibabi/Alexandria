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

int _fileSize(String? path) {
  if (path == null) return 0;
  final f = File(path);
  return f.existsSync() ? f.lengthSync() : 0;
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
      const SectionHeader('', 'Downloading', padding: EdgeInsets.fromLTRB(0, 18, 0, 8)),
      for (final e in active)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Panel(
            padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(Downloads.i.labels[e.key] ?? 'Downloading', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(value: e.value < 0 ? null : e.value),
                ]),
              ),
              IconButton(tooltip: 'Cancel', onPressed: () => Downloads.i.cancel(e.key), icon: Icon(Icons.close_sharp, color: t.muted)),
            ]),
          ),
        ),
      Text('Keeps going in the background.', style: TextStyle(color: t.muted, fontSize: 12.5)),
      const SizedBox(height: 10),
    ]);
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
        listenable: Listenable.merge([Podcasts.i, Downloads.i, Player.i]),
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
      listenable: Listenable.merge([Downloads.i, AudioLibrary.i, Player.i]),
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

  @override
  Widget build(BuildContext context) {
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
