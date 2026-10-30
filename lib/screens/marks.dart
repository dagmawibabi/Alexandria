import 'package:material_ui/material_ui.dart';

import '../core/theme.dart';
import '../core/ui.dart';
import '../models/audiobook.dart';
import '../services/audio.dart';
import '../services/folders.dart';
import '../services/library.dart';
import '../services/podcasts.dart';
import '../services/radio.dart';
import 'folders_screen.dart';

String _clock(int ms) {
  final s = ms ~/ 1000;
  final h = s ~/ 3600, m = (s % 3600) ~/ 60;
  return h > 0 ? '$h:${pad(m)}:${pad(s % 60)}' : '$m:${pad(s % 60)}';
}

/// Favourite, 1–5 rating and notes, for anything you listen to.
class MarksBar extends StatelessWidget {
  const MarksBar({super.key, required this.mark, required this.title, required this.changed, this.here, this.onSeek, this.folders, this.onFolder});

  final UserMark mark;
  final String title;

  /// Call after [mark] changed, to save it.
  final VoidCallback changed;

  /// Where playback is now, stamped on new notes.
  final ({int track, int ms}) Function()? here;
  final void Function(AudioNote)? onSeek;

  /// With both of these, a folder button sits beside Notes.
  final List<String> Function()? folders;
  final ValueChanged<String>? onFolder;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Row(children: [
      ToolButton(
        mark.favorite ? Icons.favorite_sharp : Icons.favorite_border_sharp,
        size: 40,
        active: mark.favorite,
        tooltip: mark.favorite ? 'Remove from favourites' : 'Add to favourites',
        onTap: () {
          mark.favorite = !mark.favorite;
          changed();
        },
      ),
      const SizedBox(width: 12),
      Expanded(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: RatingBar(value: mark.rating, onChanged: (v) {
            mark.rating = v;
            changed();
          }),
        ),
      ),
      const SizedBox(width: 8),
      if (folders != null && onFolder != null) ...[
        ToolButton(
          folders!().isEmpty ? Icons.folder_outlined : Icons.folder_sharp,
          size: 40,
          active: folders!().isNotEmpty,
          tooltip: 'Folders',
          onTap: () => showFolderPicker(context, title: title, selected: folders!, onToggle: onFolder!),
        ),
        const SizedBox(width: 8),
      ],
      ToolButton(
        Icons.edit_note_sharp,
        size: 40,
        label: mark.notes.isEmpty ? 'Notes' : 'Notes ${mark.notes.length}',
        color: t.ink,
        onTap: () => showNotes(context, title: title, mark: mark, changed: changed, here: here, onSeek: onSeek),
      ),
    ]);
  }
}

/// Notes on something you listen to, newest first.
Future<void> showNotes(BuildContext context, {required String title, required UserMark mark, required VoidCallback changed, ({int track, int ms}) Function()? here, void Function(AudioNote)? onSeek}) {
  final input = TextEditingController();
  return showSheet(context, builder: (ctx) {
    final t = Tokens.of(ctx);
    return StatefulBuilder(builder: (ctx, setS) {
      void add() {
        final text = input.text.trim();
        if (text.isEmpty) return;
        final at = here?.call();
        mark.notes.insert(0, AudioNote(text: text, track: at?.track ?? 0, ms: at?.ms ?? 0));
        input.clear();
        changed();
        setS(() {});
      }

      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Label('Notes', color: t.accent),
          const SizedBox(height: 4),
          Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          TextField(
            controller: input,
            minLines: 2,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(hintText: here == null ? 'Your thoughts…' : 'Your thoughts… (saved at this moment)'),
          ),
          const SizedBox(height: 8),
          PrimaryButton('Add note', icon: Icons.add_sharp, expand: true, onTap: add),
          const SizedBox(height: 14),
          for (final n in mark.notes)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Panel(
                padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
                onTap: onSeek == null
                    ? null
                    : () {
                        Navigator.pop(ctx);
                        onSeek(n);
                      },
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(n.text, style: const TextStyle(height: 1.4)),
                      const SizedBox(height: 4),
                      Label('${here != null || n.ms > 0 ? '${_clock(n.ms)}  ·  ' : ''}${pad(n.at.day)}.${pad(n.at.month)}.${n.at.year}', size: 9),
                    ]),
                  ),
                  IconButton(
                    tooltip: 'Delete note',
                    icon: Icon(Icons.close_sharp, size: 18, color: t.muted),
                    onPressed: () {
                      mark.notes.remove(n);
                      changed();
                      setS(() {});
                    },
                  ),
                ]),
              ),
            ),
        ]),
      );
    });
  });
}

/// Choose which folders something is in.
Future<void> showFolderPicker(BuildContext context, {required String title, required List<String> Function() selected, required ValueChanged<String> onToggle}) {
  return showSheet(context, builder: (ctx) {
    final t = Tokens.of(ctx);
    return ListenableBuilder(
      listenable: Listenable.merge([Library.i, AudioLibrary.i, Podcasts.i, RadioDirectory.i]),
      builder: (ctx, _) {
        final chosen = selected();
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Add to folder', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.muted, fontSize: 13.5)),
            const SizedBox(height: 14),
            for (final f in Library.i.folders)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Panel(
                  onTap: () => onToggle(f.id),
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Row(children: [
                    SizedBox(width: 36, child: FolderCover(folder: f, kind: FolderKind.books, radius: t.zen ? 8 : t.radius)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                        Text(folderContents(f), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.muted, fontSize: 12.5)),
                      ]),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(color: chosen.contains(f.id) ? t.accent : t.raised, borderRadius: BorderRadius.circular(t.zen ? 8 : t.radius), border: t.hair),
                      child: chosen.contains(f.id) ? Icon(Icons.check_sharp, size: 18, color: t.onAccent) : null,
                    ),
                  ]),
                ),
              ),
            if (Library.i.folders.isEmpty) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text('No folders yet. Make your first one.', style: TextStyle(color: t.muted))),
            PrimaryButton('New folder', ghost: true, icon: Icons.create_new_folder_outlined, expand: true, onTap: () => showFolderEditor(ctx, onCreated: (f) => onToggle(f.id))),
          ]),
        );
      },
    );
  });
}

/// The library's folders as chips, for filing a podcast or audiobook.
class FolderChips extends StatelessWidget {
  const FolderChips({super.key, required this.selected, required this.onToggle});
  final List<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return ListenableBuilder(
      listenable: Library.i,
      builder: (context, _) => Wrap(spacing: 6, runSpacing: 6, children: [
        for (final f in Library.i.folders) Tag(f.name, color: Color(f.color), filled: selected.contains(f.id), onTap: () => onToggle(f.id)),
        Tag('+ New', color: t.accent, onTap: () async {
          final n = await promptText(context, title: 'New folder', hint: 'e.g. Morning walk, History');
          if (n != null && n.trim().isNotEmpty) onToggle(Library.i.addFolder(n.trim()).id);
        }),
      ]),
    );
  }
}
