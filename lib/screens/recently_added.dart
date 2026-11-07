import 'package:material_ui/material_ui.dart';

import '../core/ui.dart';
import '../services/audio.dart';
import '../services/library.dart';
import '../services/podcasts.dart';
import 'audiobook_screen.dart';
import 'library_screen.dart' show openBook, showBookActions;
import 'player_screen.dart';
import 'podcasts_view.dart';

enum AddedKind { book, audio, show }

/// What was added in the last month, newest first. Takes no room when there's none.
class RecentlyAdded extends StatelessWidget {
  const RecentlyAdded({super.key, this.kinds = const {AddedKind.book, AddedKind.audio, AddedKind.show}, this.onSeeAll});

  final Set<AddedKind> kinds;

  /// Shows a "See all" button on the header that calls this.
  final void Function(BuildContext context)? onSeeAll;

  static const window = Duration(days: 30);
  static const _width = 96.0;

  @override
  Widget build(BuildContext context) {
    // Usually const, so a parent rebuild skips it: it has to listen for itself.
    return ListenableBuilder(listenable: Listenable.merge([Library.i, AudioLibrary.i, Podcasts.i]), builder: (context, _) => _rail(context));
  }

  Widget _rail(BuildContext context) {
    final since = DateTime.now().subtract(window);
    final items = <(DateTime, Widget)>[
      if (kinds.contains(AddedKind.book))
        for (final b in Library.i.books.where((b) => b.addedAt.isAfter(since)))
          (
            b.addedAt,
            _AddedTile(
              art: Cover(b),
              title: b.title,
              kind: b.formatLabel,
              onTap: () => openBook(context, b),
              onLongPress: () => showBookActions(context, b),
            ),
          ),
      if (kinds.contains(AddedKind.audio))
        for (final b in AudioLibrary.i.books.where((b) => b.addedAt.isAfter(since)))
          (
            b.addedAt,
            _AddedTile(
              art: AudioCover(b),
              title: b.title,
              kind: 'Audiobook',
              onTap: () => openAudiobook(context, b),
              onLongPress: () => showAudiobookActions(context, b),
            ),
          ),
      if (kinds.contains(AddedKind.show))
        for (final x in Podcasts.i.subscriptions.where((x) => x.subscribedAt?.isAfter(since) ?? false))
          (
            x.subscribedAt!,
            _AddedTile(
              art: PodcastArt(x.imageUrl, title: x.title),
              title: x.title,
              kind: 'Podcast',
              onTap: () => openPodcast(context, feedUrl: x.feedUrl),
              onLongPress: () => showShowMenu(context, x),
            ),
          ),
    ]..sort((a, b) => b.$1.compareTo(a.$1));
    if (items.isEmpty) return const SizedBox.shrink();
    final scale = MediaQuery.textScalerOf(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionHeader(
        '',
        'Recently added',
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
        trailing: onSeeAll == null ? null : SeeAll(onTap: () => onSeeAll!(context)),
      ),
      SizedBox(
        height: _width * 1.5 + 6 + scale.scale(32) + 4 + scale.scale(14),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: items.length.clamp(0, 14),
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (_, i) => SizedBox(width: _width, child: items[i].$2),
        ),
      ),
    ]);
  }
}

class _AddedTile extends StatelessWidget {
  const _AddedTile({required this.art, required this.title, required this.kind, required this.onTap, required this.onLongPress});
  final Widget art;
  final String title;
  final String kind;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: () {
        haptic(true);
        onLongPress();
      },
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Book covers are tall and the others square; a shared height lines up the titles.
        SizedBox(height: RecentlyAdded._width * 1.5, child: Align(alignment: Alignment.bottomCenter, child: art)),
        const SizedBox(height: 6),
        Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, height: 1.15)),
        const SizedBox(height: 4),
        Label(kind, size: 9),
      ]),
    );
  }
}
