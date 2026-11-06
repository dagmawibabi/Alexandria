import 'package:material_ui/material_ui.dart';

import '../core/theme.dart';
import '../core/ui.dart';
import '../models/audiobook.dart';
import '../services/audio.dart';
import '../services/downloads.dart';
import '../services/library.dart';
import 'marks.dart';
import 'media_card.dart';
import 'player_screen.dart';
import '../core/image_viewer.dart';

void openAudiobook(BuildContext context, Audiobook b) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AudiobookScreen(book: b)));

/// One audiobook: play it, rate it, take notes, file it in folders, see its chapters.
class AudiobookScreen extends StatelessWidget {
  const AudiobookScreen({super.key, required this.book});
  final Audiobook book;

  String _source(Audiobook b) => switch (b.source) { 'librivox' => 'LibriVox', 'archive' => 'Internet Archive', _ => 'Your files' };

  Future<void> _seekTo(BuildContext context, AudioNote n) async {
    if (Player.i.book?.id != book.id) await Player.i.open(book);
    await Player.i.goTo(n.track, n.ms);
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final b = book;
    return Scaffold(
      appBar: AppBar(title: AppTitle(t.zen ? b.title : 'Audiobook'), actions: [
        IconButton(tooltip: 'Share card', onPressed: () => showMediaCard(context, ShareItem.audiobook(b)), icon: const Icon(Icons.ios_share_sharp)),
        IconButton(tooltip: 'More', onPressed: () => showAudiobookActions(context, b, fromPlayer: true), icon: const Icon(Icons.more_horiz_sharp)),
      ]),
      body: ListenableBuilder(
        listenable: Listenable.merge([AudioLibrary.i, Downloads.i, Player.i, Library.i]),
        builder: (context, _) {
          final pl = Player.i;
          final current = pl.book?.id == b.id;
          final text = AudioLibrary.i.bookFor(b);
          final dl = Downloads.i.progress[b.id];
          final saved = b.tracks.where((x) => x.downloaded).length;
          final facts = [
            if (b.tracks.length > 1) '${b.tracks.length} chapters',
            if (b.timed) fmtDuration(b.totalMs ~/ 1000),
            _source(b),
            if (b.year.isNotEmpty) b.year,
          ].join(' · ');
          return ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 40), children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 128, child: ViewableImage(path: b.coverPath, url: b.coverUrl, title: b.title, child: AudioCover(b))),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(b.title, maxLines: 4, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700, height: 1.15, letterSpacing: -.3)),
                  if (b.author.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(b.author, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.muted, fontSize: 14.5))),
                  if (b.narrator.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text('Read by ${b.narrator}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.muted, fontSize: 13))),
                  const SizedBox(height: 8),
                  Text(facts, style: TextStyle(color: t.muted, fontSize: 12.5, height: 1.35)),
                ]),
              ),
            ]),
            const SizedBox(height: 16),
            if (b.progress > 0) ...[
              ClipRRect(borderRadius: BorderRadius.circular(2), child: LinearProgressIndicator(value: b.progress, minHeight: 4)),
              const SizedBox(height: 6),
              Label(b.finished ? 'Finished' : '${(b.progress * 100).round()}% · chapter ${b.trackIndex + 1} of ${b.tracks.length}', size: 9.5),
              const SizedBox(height: 12),
            ],
            Row(children: [
              Expanded(
                child: PrimaryButton(
                  current && pl.playing ? 'Now playing' : (b.finished ? 'Listen again' : (b.progress > 0 ? 'Resume' : 'Play')),
                  icon: current && pl.playing ? Icons.graphic_eq_sharp : Icons.play_arrow_sharp,
                  onTap: () => playAudiobook(context, b),
                ),
              ),
              if (text != null) ...[
                const SizedBox(width: 8),
                ToolButton(Icons.menu_book_sharp, size: 48, tooltip: 'Read along', onTap: () => readAlong(context, b, text)),
              ],
              if (b.downloadable || dl != null) ...[
                const SizedBox(width: 8),
                ToolButton(
                  dl != null ? Icons.close_sharp : Icons.download_sharp,
                  size: 48,
                  label: dl != null ? 'Cancel' : (saved > 0 ? 'Download rest' : 'Download all'),
                  tooltip: dl != null ? 'Cancel download' : 'Download every chapter',
                  onTap: () async {
                    if (dl != null) return Downloads.i.cancel(b.id);
                    final ok = await AudioLibrary.i.download(b);
                    if (context.mounted && !ok && !Downloads.i.cancelled(b.id)) toast(context, 'Download stopped. Tap again to resume.');
                  },
                ),
              ],
            ]),
            if (dl != null) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(value: dl < 0 ? null : dl),
            ] else if (saved > 0) ...[
              const SizedBox(height: 8),
              Label(saved == b.tracks.length ? 'All chapters downloaded' : '$saved of ${b.tracks.length} chapters downloaded', size: 9.5),
            ],
            const SizedBox(height: 16),
            MarksBar(
              mark: b.mark,
              title: b.title,
              changed: () => AudioLibrary.i.touch(b),
              here: () => (track: b.trackIndex, ms: b.positionMs),
              onSeek: (n) => _seekTo(context, n),
              folders: () => b.folderIds,
              onFolder: (id) => AudioLibrary.i.toggleFolder(b, id),
            ),
            if (b.mark.notes.isNotEmpty) ...[
              SectionHeader('', 'Notes · ${b.mark.notes.length}', padding: const EdgeInsets.fromLTRB(0, 24, 0, 10)),
              for (final n in b.mark.notes.take(3))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Panel(
                    onTap: () => _seekTo(context, n),
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(n.text, style: const TextStyle(height: 1.4)),
                      const SizedBox(height: 4),
                      Label('Chapter ${n.track + 1} · ${fmtClock(Duration(milliseconds: n.ms))}', size: 9),
                    ]),
                  ),
                ),
              if (b.mark.notes.length > 3)
                GestureDetector(
                  onTap: () => showNotes(context, title: b.title, mark: b.mark, changed: () => AudioLibrary.i.touch(b), here: () => (track: b.trackIndex, ms: b.positionMs), onSeek: (n) => _seekTo(context, n)),
                  child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Label('All notes', color: t.accent, weight: FontWeight.w600)),
                ),
            ],
            if (b.description.isNotEmpty) ...[
              const SectionHeader('', 'About', padding: EdgeInsets.fromLTRB(0, 24, 0, 10)),
              CollapsibleText(b.description, lines: 5, style: TextStyle(height: 1.5, color: t.ink.withValues(alpha: .85))),
            ],
            SectionHeader('', 'Chapters · ${b.tracks.length}', padding: const EdgeInsets.fromLTRB(0, 24, 0, 4)),
            for (var i = 0; i < b.tracks.length; i++)
              InkWell(
                onTap: () => playAudiobook(context, b, track: i),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.line))),
                  child: Row(children: [
                    SizedBox(width: 34, child: Label(pad(i + 1), color: i == b.trackIndex ? t.accent : t.muted)),
                    Expanded(child: Text(b.tracks[i].title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: i == b.trackIndex ? FontWeight.w700 : FontWeight.w500))),
                    if (b.tracks[i].ms > 0) Label(fmtClock(Duration(milliseconds: b.tracks[i].ms))),
                    ChapterDownload(book: b, index: i),
                  ]),
                ),
              ),
          ]);
        },
      ),
    );
  }
}
