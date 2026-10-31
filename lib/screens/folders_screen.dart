import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../core/settings.dart';
import '../core/search_box.dart';
import '../core/theme.dart';
import '../core/ui.dart';
import '../models/book.dart';
import '../services/audio.dart';
import '../services/folders.dart';
import '../services/library.dart';
import '../services/podcasts.dart';
import '../services/radio.dart';
import 'audiobook_screen.dart';
import 'book_info_screen.dart';
import 'library_screen.dart';
import 'player_screen.dart';
import 'podcasts_view.dart';
import 'radio_view.dart';

Listenable get _everything => Listenable.merge([Library.i, AudioLibrary.i, Podcasts.i, RadioDirectory.i]);

void openFolders(BuildContext context, FolderKind kind) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => FoldersScreen(kind: kind)));

/// One thing that can go in a folder, whichever kind it is.
class _Item {
  const _Item({required this.key, required this.title, required this.subtitle, required this.art, required this.artWidth, required this.folders, required this.toggle, required this.open, this.menu, this.rating = 0, this.favorite = false, this.when});
  final String key;
  final String title;
  final String subtitle;
  final Widget art;
  final double artWidth;
  final List<String> folders;
  final ValueChanged<String> toggle;
  final void Function(BuildContext) open;
  final void Function(BuildContext)? menu;
  final int rating;
  final bool favorite;
  final DateTime? when;
}

List<_Item> _items(FolderKind kind) => switch (kind) {
      FolderKind.books => [
          for (final b in Library.i.books)
            _Item(
              key: b.id,
              title: b.title,
              subtitle: b.author,
              art: Cover(b),
              artWidth: 38,
              folders: b.folderIds,
              toggle: (id) => Library.i.toggleFolder(b, Library.i.folders.firstWhere((f) => f.id == id)),
              open: (c) => openBook(c, b),
              menu: (c) => showBookActions(c, b),
              rating: b.rating,
              favorite: b.favorite,
              when: b.lastOpenedAt ?? b.addedAt,
            ),
          for (final s in Library.i.saved)
            _Item(
              key: s.key,
              title: s.title,
              subtitle: [s.author, s.wanted ? 'Want to read' : 'Not in your library'].where((x) => x.isNotEmpty).join(' · '),
              art: NetCover(url: s.coverUrl, title: s.title),
              artWidth: 38,
              folders: s.folderIds,
              toggle: (id) => Library.i.toggleSavedFolder(s, id),
              open: (c) => openBookInfo(c, infoFrom(s)),
              menu: (c) => showBookMarks(c, infoFrom(s)),
              rating: s.mark.rating,
              favorite: s.mark.favorite,
              when: s.savedAt,
            ),
        ],
      FolderKind.audio => [
          for (final b in AudioLibrary.i.books)
            _Item(
              key: b.id,
              title: b.title,
              subtitle: b.author,
              art: AudioCover(b, shadow: false),
              artWidth: 48,
              folders: b.folderIds,
              toggle: (id) => AudioLibrary.i.toggleFolder(b, id),
              open: (c) => openAudiobook(c, b),
              menu: (c) => showAudiobookActions(c, b),
              rating: b.mark.rating,
              favorite: b.mark.favorite,
              when: b.lastPlayedAt ?? b.addedAt,
            ),
        ],
      FolderKind.podcasts => [
          for (final s in Podcasts.i.subscriptions)
            _Item(
              key: s.feedUrl,
              title: s.title,
              subtitle: s.author,
              art: PodcastArt(s.imageUrl, title: s.title),
              artWidth: 48,
              folders: Podcasts.i.foldersOf(s.feedUrl),
              toggle: (id) => Podcasts.i.toggleFolder(s.feedUrl, id),
              open: (c) => openPodcast(c, feedUrl: s.feedUrl),
              menu: (c) => showShowMenu(c, s),
              rating: Podcasts.i.showMark(s.feedUrl).rating,
              favorite: Podcasts.i.showMark(s.feedUrl).favorite,
              when: s.subscribedAt,
            ),
        ],
      FolderKind.radio => [
          for (final s in RadioDirectory.i.kept)
            _Item(
              key: s.id,
              title: s.name,
              subtitle: s.subtitle,
              art: PodcastArt(s.favicon, title: s.name),
              artWidth: 48,
              folders: RadioDirectory.i.foldersOf(s.id),
              toggle: (id) => RadioDirectory.i.toggleFolder(s, id),
              open: (_) => RadioDirectory.i.play(s),
              menu: (c) => showStationMenu(c, s),
              rating: RadioDirectory.i.markOf(s.id).rating,
              favorite: RadioDirectory.i.isFavorite(s.id),
            ),
        ],
    };

/// A folder's picture: the one you chose, or else what's inside it.
class FolderCover extends StatelessWidget {
  const FolderCover({super.key, required this.folder, required this.kind, this.radius});
  final Folder folder;
  final FolderKind kind;
  final double? radius;

  /// [art] cropped to fill its cell, whatever its own shape.
  Widget _cell(_Item i) => ClipRect(child: FittedBox(fit: BoxFit.cover, child: SizedBox(width: 100, height: i.artWidth < 40 ? 150 : 100, child: i.art)));

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final path = folder.coverPath;
    final Widget child;
    if (path != null && File(path).existsSync()) {
      child = monoImage(Image.file(File(path), fit: BoxFit.cover, gaplessPlayback: true));
    } else {
      // This tab's things first; a folder holding only other kinds still shows those.
      var inside = _items(kind).where((x) => x.folders.contains(folder.id)).take(4).toList();
      if (inside.isEmpty) {
        for (final k in FolderKind.values) {
          inside = _items(k).where((x) => x.folders.contains(folder.id)).take(4).toList();
          if (inside.isNotEmpty) break;
        }
      }
      if (inside.isEmpty) {
        child = ColoredBox(color: Color(folder.color).withValues(alpha: .16), child: Center(child: FractionallySizedBox(widthFactor: .42, child: FittedBox(child: Icon(Icons.folder_sharp, color: Color(folder.color))))));
      } else if (inside.length == 1) {
        child = _cell(inside.first);
      } else {
        // One, two or three tiles fill the shape, so nothing inside is hidden.
        final rows = switch (inside.length) {
          2 => [[inside[0]], [inside[1]]],
          3 => [[inside[0]], [inside[1], inside[2]]],
          _ => [[inside[0], inside[1]], [inside[2], inside[3]]],
        };
        child = Column(children: [
          for (final row in rows) Expanded(child: Row(children: [for (final i in row) Expanded(child: SizedBox.expand(child: _cell(i)))])),
        ]);
      }
    }
    // Portrait, like a book, so the covers inside show properly.
    return AspectRatio(
      aspectRatio: 2 / 3,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: t.raised, borderRadius: BorderRadius.circular(radius ?? (t.zen ? 12 : t.radius + 2)), border: t.hair),
        child: child,
      ),
    );
  }
}

/// Name, picture and colour for a new folder, or an existing one (which can also be deleted).
Future<void> showFolderEditor(BuildContext context, {Folder? folder, ValueChanged<Folder>? onCreated, VoidCallback? onDeleted}) {
  final name = TextEditingController(text: folder?.name ?? '');
  var color = folder?.color ?? accents[Library.i.folders.length % accents.length].toARGB32();
  String? picked;
  var clearCover = false;
  return showSheet(context, builder: (ctx) {
    final t = Tokens.of(ctx);
    return StatefulBuilder(builder: (ctx, setS) {
      Future<void> save() async {
        final n = name.text.trim();
        if (n.isEmpty) return;
        final Folder f;
        if (folder == null) {
          f = Library.i.addFolder(n, color: color);
        } else {
          f = folder;
          Library.i.renameFolder(f, n);
          Library.i.recolorFolder(f, color);
        }
        if (picked != null) {
          await Library.i.setFolderCover(f, picked);
        } else if (clearCover) {
          await Library.i.setFolderCover(f, null);
        }
        if (ctx.mounted) Navigator.pop(ctx);
        if (folder == null) onCreated?.call(f);
      }

      final shown = picked ?? (clearCover ? null : folder?.coverPath);

      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(folder == null ? 'New folder' : 'Edit folder', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          TextField(
            controller: name,
            autofocus: folder == null,
            textCapitalization: TextCapitalization.sentences,
            onSubmitted: (_) => save(),
            decoration: const InputDecoration(hintText: 'e.g. Philosophy, Morning walk, Work'),
          ),
          const SizedBox(height: 16),
          const Label('Cover image'),
          const SizedBox(height: 8),
          Row(children: [
            SizedBox(
              width: 72,
              child: shown != null && File(shown).existsSync()
                  ? AspectRatio(aspectRatio: 2 / 3, child: ClipRRect(borderRadius: BorderRadius.circular(t.zen ? 12 : t.radius + 2), child: monoImage(Image.file(File(shown), fit: BoxFit.cover))))
                  : (folder != null && !clearCover
                      ? FolderCover(folder: folder, kind: FolderKind.books)
                      : AspectRatio(aspectRatio: 2 / 3, child: Container(decoration: BoxDecoration(color: Color(color).withValues(alpha: .16), borderRadius: BorderRadius.circular(t.zen ? 12 : t.radius + 2)), child: Icon(Icons.folder_sharp, color: Color(color))))),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ToolButton(Icons.image_outlined, label: shown == null ? 'Choose image' : 'Change', size: 38, onTap: () async {
                  final files = await FilePicker.pickFiles(type: FileType.image);
                  final path = files.firstOrNull?.path;
                  if (path != null) setS(() => picked = path);
                }),
                const SizedBox(height: 6),
                if (shown != null)
                  GestureDetector(
                    onTap: () => setS(() {
                      picked = null;
                      clearCover = true;
                    }),
                    child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Label('Use what\'s inside', color: t.accent, weight: FontWeight.w600)),
                  )
                else
                  Text('Otherwise it shows what\'s inside.', style: TextStyle(color: t.muted, fontSize: 12.5)),
              ]),
            ),
          ]),
          const SizedBox(height: 16),
          const Label('Colour'),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in [...accents, ...highlightColors])
              GestureDetector(
                onTap: () {
                  haptic();
                  setS(() => color = c.toARGB32());
                },
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(color: c, borderRadius: t.br, border: Border.all(color: color == c.toARGB32() ? t.ink : Colors.transparent, width: 2.5)),
                  child: color == c.toARGB32() ? Icon(Icons.check_sharp, size: 18, color: c.computeLuminance() > .5 ? Colors.black : Colors.white) : null,
                ),
              ),
          ]),
          const SizedBox(height: 20),
          PrimaryButton(folder == null ? 'Create folder' : 'Save', expand: true, onTap: save),
          if (folder != null) ...[
            const SizedBox(height: 8),
            PrimaryButton('Delete folder', ghost: true, icon: Icons.delete_outline_sharp, expand: true, onTap: () async {
              final ok = await confirm(ctx, 'Delete "${folder.name}"', 'Holds ${folderContents(folder).toLowerCase()}. Nothing in it is deleted; only the folder goes, on every tab.');
              if (!ok) return;
              Library.i.deleteFolder(folder);
              if (ctx.mounted) Navigator.pop(ctx);
              onDeleted?.call();
            }),
          ],
        ]),
      );
    });
  });
}

/// All folders, for one tab's kind of thing.
class FoldersScreen extends StatelessWidget {
  const FoldersScreen({super.key, required this.kind});
  final FolderKind kind;

  void _open(BuildContext context, {Folder? folder, String? smart}) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => _FolderContents(kind: kind, folder: folder, smart: smart)));
  }

  Future<void> _create(BuildContext context) => showFolderEditor(context, onCreated: (f) {
        if (context.mounted) _open(context, folder: f);
      });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Scaffold(
      appBar: AppBar(title: AppTitle(kind.title), actions: [
        ListenableBuilder(
          listenable: Settings.i,
          builder: (_, _) => IconButton(
            tooltip: Settings.i.folderGrid ? 'List view' : 'Grid view',
            onPressed: () => Settings.i.folderGrid = !Settings.i.folderGrid,
            icon: Icon(Settings.i.folderGrid ? Icons.view_agenda_outlined : Icons.grid_view_sharp),
          ),
        ),
        Padding(padding: const EdgeInsets.only(right: 12), child: ToolButton(Icons.create_new_folder_outlined, label: 'New', active: true, size: 38, onTap: () => _create(context))),
      ]),
      body: ListenableBuilder(
        listenable: Listenable.merge([_everything, Settings.i]),
        builder: (context, _) {
          final folders = Library.i.folders;
          final favs = _items(kind).where((i) => i.favorite).length;
          return ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 40), children: [
            _SmartRow(icon: Icons.favorite_border_sharp, title: 'Favourites', count: countOf(favs, kind), onTap: () => _open(context, smart: 'fav')),
            _SmartRow(icon: Icons.inbox_outlined, title: 'Not in a folder', count: countOf(unfiledCount(kind), kind), onTap: () => _open(context, smart: 'none')),
            SectionHeader('', 'Your folders · ${folders.length}', padding: const EdgeInsets.fromLTRB(0, 18, 0, 10)),
            if (folders.isEmpty)
              Panel(
                padding: const EdgeInsets.all(22),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.folder_outlined, color: t.accent, size: 28),
                  const SizedBox(height: 10),
                  const Text('No folders yet', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('Group your ${kind.plural} any way you like. A folder can hold books, audiobooks and shows together.', style: TextStyle(color: t.muted, height: 1.4)),
                  const SizedBox(height: 14),
                  PrimaryButton('Create a folder', icon: Icons.add_sharp, onTap: () => _create(context)),
                ]),
              )
            else if (Settings.i.folderGrid)
              LayoutBuilder(builder: (context, c) {
                final w = (c.maxWidth - 24) / 3;
                return Wrap(spacing: 12, runSpacing: 16, children: [
                  for (final f in folders)
                    GestureDetector(
                      onTap: () => _open(context, folder: f),
                      onLongPress: () {
                        haptic(true);
                        showFolderEditor(context, folder: f);
                      },
                      child: SizedBox(
                        width: w,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          FolderCover(folder: f, kind: kind),
                          const SizedBox(height: 8),
                          Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                          const SizedBox(height: 1),
                          Text(countOf(folderCount(kind, f.id), kind), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.muted, fontSize: 12.5)),
                        ]),
                      ),
                    ),
                ]);
              })
            else
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: folders.length,
                onReorderItem: (a, b) => Library.i.reorderFolders(a, b > a ? b + 1 : b),
                itemBuilder: (context, i) {
                  final f = folders[i];
                  return Padding(
                    key: ValueKey(f.id),
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Panel(
                      onTap: () => _open(context, folder: f),
                      padding: const EdgeInsets.fromLTRB(12, 10, 2, 10),
                      child: Row(children: [
                        SizedBox(width: 44, child: FolderCover(folder: f, kind: kind, radius: t.zen ? 8 : t.radius)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15.5)),
                            const SizedBox(height: 2),
                            Text(countOf(folderCount(kind, f.id), kind), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.muted, fontSize: 13)),
                          ]),
                        ),
                        IconButton(tooltip: 'Edit folder', onPressed: () => showFolderEditor(context, folder: f), icon: Icon(Icons.more_horiz_sharp, color: t.muted)),
                        ReorderableDragStartListener(index: i, child: Padding(padding: const EdgeInsets.fromLTRB(2, 8, 8, 8), child: Icon(Icons.drag_handle_sharp, color: t.muted))),
                      ]),
                    ),
                  );
                },
              ),
            if (folders.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Folders are shared across the app, so one can hold books, audiobooks and shows together. This page shows your ${kind.plural}.${Settings.i.folderGrid ? ' Hold a folder to edit it.' : ' Drag to reorder.'}', style: TextStyle(color: t.muted, fontSize: 12.5, height: 1.4)),
            ],
          ]);
        },
      ),
    );
  }
}

class _SmartRow extends StatelessWidget {
  const _SmartRow({required this.icon, required this.title, required this.count, required this.onTap});
  final IconData icon;
  final String title;
  final String count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Panel(
        onTap: onTap,
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
        child: Row(children: [
          SizedBox(width: 42, child: Icon(icon, color: t.accent, size: 22)),
          const SizedBox(width: 12),
          Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15.5))),
          Text(count, style: TextStyle(color: t.muted, fontSize: 13)),
          Icon(Icons.chevron_right_sharp, color: t.muted),
        ]),
      ),
    );
  }
}

/// What's in a folder (or a smart view like Favourites).
class _FolderContents extends StatefulWidget {
  const _FolderContents({required this.kind, this.folder, this.smart});
  final FolderKind kind;
  final Folder? folder;

  /// 'fav' or 'none', when there's no [folder].
  final String? smart;

  @override
  State<_FolderContents> createState() => _FolderContentsState();
}

class _FolderContentsState extends State<_FolderContents> {
  final _q = TextEditingController();
  String _sort = 'recent';

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  List<_Item> _shown() {
    final live = {for (final f in Library.i.folders) f.id};
    final q = _q.text.trim().toLowerCase();
    final list = _items(widget.kind).where((i) {
      final inView = widget.folder != null ? i.folders.contains(widget.folder!.id) : (widget.smart == 'fav' ? i.favorite : !i.folders.any(live.contains));
      return inView && (q.isEmpty || '${i.title} ${i.subtitle}'.toLowerCase().contains(q));
    }).toList();
    switch (_sort) {
      case 'title':
        list.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      case 'rating':
        list.sort((a, b) => b.rating.compareTo(a.rating));
      default:
        list.sort((a, b) => (b.when ?? DateTime(1970)).compareTo(a.when ?? DateTime(1970)));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final f = widget.folder;
    final kind = widget.kind;
    const sorts = {'recent': 'Recent', 'title': 'Title', 'rating': 'Rating'};
    return ListenableBuilder(
      listenable: Listenable.merge([_everything, Settings.i]),
      builder: (context, _) {
        final items = _shown();
        final grid = Settings.i.folderGrid;
        return Scaffold(
          bottomNavigationBar: const PagePlayer(),
          appBar: AppBar(
            title: AppTitle(f?.name ?? (widget.smart == 'fav' ? 'Favourites' : 'Not in a folder')),
            actions: [
              IconButton(
                tooltip: grid ? 'List view' : 'Grid view',
                onPressed: () => Settings.i.folderGrid = !grid,
                icon: Icon(grid ? Icons.view_agenda_outlined : Icons.grid_view_sharp),
              ),
              if (f != null) IconButton(tooltip: 'Edit folder', onPressed: () => showFolderEditor(context, folder: f, onDeleted: () => Navigator.of(context).maybePop()), icon: const Icon(Icons.edit_outlined)),
            ],
          ),
          body: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 40), children: [
            if (f != null) ...[
              Row(children: [
                GestureDetector(onTap: () => showFolderEditor(context, folder: f), child: SizedBox(width: 84, child: FolderCover(folder: f, kind: kind))),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(f.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, height: 1.15)),
                    const SizedBox(height: 3),
                    Text(folderContents(f), style: TextStyle(color: t.muted, fontSize: 13)),
                    const SizedBox(height: 10),
                    ToolButton(Icons.playlist_add_sharp, label: 'Add ${kind.plural}', active: true, size: 38, onTap: () => _picker(context, f)),
                  ]),
                ),
              ]),
              const SizedBox(height: 14),
            ],
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: SearchBox(historyKey: 'folder', 
                  controller: _q,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(hintText: 'Search here', prefixIcon: const Icon(Icons.search_sharp, size: 18)),
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                onSelected: (v) => setState(() => _sort = v),
                itemBuilder: (_) => [for (final e in sorts.entries) PopupMenuItem(value: e.key, child: Text(e.value))],
                child: Tag(sorts[_sort]!),
              ),
            ]),
            const SizedBox(height: 8),
            Label(countOf(items.length, kind), size: 9.5),
            const SizedBox(height: 6),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Text(
                  _q.text.isNotEmpty ? 'Nothing matches that search.' : (f != null ? (kind == FolderKind.radio ? 'Nothing in here yet. Add stations you\'ve played or favourited, or tap any station in Global Radio and use its folder button.' : 'Nothing in here yet. Tap Add ${kind.plural}.') : 'Nothing here.'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: t.muted),
                ),
              ),
            if (grid)
              LayoutBuilder(builder: (context, c) {
                final w = (c.maxWidth - 24) / 3;
                return Wrap(spacing: 12, runSpacing: 16, children: [
                  for (final i in items)
                    GestureDetector(
                      onTap: () => i.open(context),
                      onLongPress: i.menu == null
                          ? null
                          : () {
                              haptic(true);
                              i.menu!(context);
                            },
                      child: SizedBox(
                        width: w,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Stack(children: [
                            i.art,
                            if (f != null)
                              Positioned(
                                right: 4,
                                top: 4,
                                child: GestureDetector(
                                  onTap: () {
                                    haptic();
                                    i.toggle(f.id);
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: .55), borderRadius: BorderRadius.circular(7)),
                                    child: const Icon(Icons.close_sharp, size: 14, color: Colors.white),
                                  ),
                                ),
                              ),
                            if (i.favorite) Positioned(left: 5, top: 5, child: Icon(Icons.favorite_sharp, size: 14, color: t.accent)),
                          ]),
                          const SizedBox(height: 6),
                          Text(i.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.15)),
                          if (i.rating > 0)
                            Padding(padding: const EdgeInsets.only(top: 3), child: Row(children: [for (var n = 0; n < i.rating; n++) Icon(Icons.star_sharp, size: 11, color: t.accent)])),
                        ]),
                      ),
                    ),
                ]);
              }),
            if (!grid)
              for (final i in items)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => i.open(context),
                onLongPress: i.menu == null
                    ? null
                    : () {
                        haptic(true);
                        i.menu!(context);
                      },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.line))),
                  child: Row(children: [
                    SizedBox(width: i.artWidth, child: i.art),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(i.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, height: 1.2)),
                        if (i.subtitle.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(i.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.muted, fontSize: 12.5))),
                        if (i.rating > 0 || i.favorite)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Row(children: [
                              if (i.favorite) Padding(padding: const EdgeInsets.only(right: 6), child: Icon(Icons.favorite_sharp, size: 12, color: t.accent)),
                              for (var n = 0; n < i.rating; n++) Icon(Icons.star_sharp, size: 12, color: t.accent),
                            ]),
                          ),
                      ]),
                    ),
                    if (f != null) IconButton(tooltip: 'Remove from folder', onPressed: () => i.toggle(f.id), icon: Icon(Icons.close_sharp, size: 18, color: t.muted)),
                    if (f == null && i.menu != null) IconButton(tooltip: 'More', onPressed: () => i.menu!(context), icon: Icon(Icons.more_horiz_sharp, color: t.muted)),
                  ]),
                ),
              ),
          ]),
        );
      },
    );
  }

  /// Tick things in or out of the folder.
  void _picker(BuildContext context, Folder f) {
    final kind = widget.kind;
    showSheet(context, scroll: false, maxHeight: .9, builder: (ctx) {
      var q = '';
      return StatefulBuilder(builder: (ctx, setS) {
        final t = Tokens.of(ctx);
        return ListenableBuilder(
          listenable: _everything,
          builder: (ctx, _) {
            final all = _items(kind).where((i) => q.isEmpty || '${i.title} ${i.subtitle}'.toLowerCase().contains(q)).toList()..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text('Add to ${f.name}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
                  GestureDetector(onTap: () => Navigator.pop(ctx), child: Label('Done', color: t.accent, weight: FontWeight.w600)),
                ]),
                const SizedBox(height: 10),
                SearchBox(historyKey: 'folder-add', onChanged: (v) => setS(() => q = v.trim().toLowerCase()), decoration: InputDecoration(hintText: 'Search your ${kind.plural}', prefixIcon: const Icon(Icons.search_sharp, size: 18))),
                const SizedBox(height: 6),
                Expanded(
                  child: all.isEmpty
                      ? Center(child: Text(kindTotal(kind) == 0 ? 'You have no ${kind.plural} yet.' : 'Nothing matches.', style: TextStyle(color: t.muted)))
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 24),
                          itemCount: all.length,
                          itemBuilder: (_, n) {
                            final i = all[n];
                            final on = i.folders.contains(f.id);
                            return GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                haptic();
                                i.toggle(f.id);
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                child: Row(children: [
                                  SizedBox(width: i.artWidth, child: i.art),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text(i.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                                      if (i.subtitle.isNotEmpty) Text(i.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.muted, fontSize: 12.5)),
                                    ]),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    width: 26,
                                    height: 26,
                                    decoration: BoxDecoration(color: on ? t.accent : t.raised, borderRadius: BorderRadius.circular(t.zen ? 8 : t.radius), border: t.hair),
                                    child: on ? Icon(Icons.check_sharp, size: 18, color: t.onAccent) : null,
                                  ),
                                ]),
                              ),
                            );
                          },
                        ),
                ),
              ]),
            );
          },
        );
      });
    });
  }
}
