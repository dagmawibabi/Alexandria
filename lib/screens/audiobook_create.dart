import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../core/net_image.dart';
import '../core/theme.dart';
import '../core/ui.dart';
import '../models/book.dart';
import '../services/audio.dart';
import '../services/free_audio.dart';
import '../services/metadata.dart';
import 'meta_search.dart';
import 'player_screen.dart';

/// Picks audio files and opens the audiobook set-up page.
Future<void> addAudiobookFromFiles(BuildContext context) async {
  final picked = await FilePicker.pickFiles(type: FileType.audio, dialogTitle: 'Choose the audiobook\'s files');
  final files = [for (final f in picked) if (f.path != null) (path: f.path!, name: f.name)];
  if (files.isEmpty || !context.mounted) return;
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => AudiobookCreateScreen(files: files)));
}

/// "Track 2" sorts before "Track 10".
String _naturalKey(String s) => s.toLowerCase().replaceAllMapped(RegExp(r'\d+'), (m) => m[0]!.padLeft(8, '0'));

/// A title guess from the file names: their shared start, or the first file's name.
String guessTitle(List<String> names) {
  final clean = names.map((n) => n.replaceAll(RegExp(r'\.[A-Za-z0-9]{2,4}$'), '').replaceAll('_', ' ')).toList();
  var prefix = clean.first;
  for (final n in clean.skip(1)) {
    var i = 0;
    while (i < prefix.length && i < n.length && prefix[i].toLowerCase() == n[i].toLowerCase()) {
      i++;
    }
    prefix = prefix.substring(0, i);
  }
  prefix = prefix.replaceAll(RegExp(r'[\s\-_.:(\[]*((part|chapter|track|cd|disc|ch)\s*)?\d*\s*$', caseSensitive: false), '').trim();
  if (prefix.length >= 3) return prefix;
  return cleanTrackTitle(names.first);
}

class AudiobookCreateScreen extends StatefulWidget {
  const AudiobookCreateScreen({super.key, required this.files});
  final List<({String path, String name})> files;

  @override
  State<AudiobookCreateScreen> createState() => _AudiobookCreateScreenState();
}

class _AudiobookCreateScreenState extends State<AudiobookCreateScreen> {
  late final List<({String path, String name})> _files = [...widget.files]..sort((a, b) => _naturalKey(a.name).compareTo(_naturalKey(b.name)));
  late final _title = TextEditingController(text: guessTitle(_files.map((f) => f.name).toList()));
  final _author = TextEditingController();
  final _desc = TextEditingController();
  String _year = '';
  String? _coverUrl;
  String? _coverFile;
  BookInfo? _match;

  /// The ebook this narrates, if the user attaches one.
  Book? _book;
  bool _looking = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _autoFill();
  }

  @override
  void dispose() {
    _title.dispose();
    _author.dispose();
    _desc.dispose();
    super.dispose();
  }

  /// Looks the guessed title up in the catalogues and fills the form.
  Future<void> _autoFill() async {
    final info = await Metadata.best(_title.text, '');
    if (!mounted) return;
    setState(() => _looking = false);
    if (info != null) _apply(info);
  }

  void _apply(BookInfo info) {
    setState(() {
      _match = info;
      if (info.title.isNotEmpty) _title.text = info.title;
      if (info.author.isNotEmpty) _author.text = info.author;
      if (info.description.isNotEmpty) _desc.text = info.description;
      _year = info.year;
      if (info.coverUrl != null && _coverFile == null) _coverUrl = info.coverUrl;
    });
  }

  Future<void> _search() async {
    final info = await showMetadataSearch(context, query: _title.text, author: _author.text);
    if (info != null) _apply(info);
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) return toast(context, 'Give it a title');
    setState(() => _saving = true);
    try {
      final b = await AudioLibrary.i.createLocal(
        files: _files,
        title: _title.text.trim(),
        author: _author.text.trim(),
        description: _desc.text.trim(),
        year: _year,
        coverUrl: _coverFile == null ? _coverUrl : null,
        coverFile: _coverFile,
      );
      if (_book != null) AudioLibrary.i.linkBook(b, _book);
      if (!mounted) return;
      Navigator.pop(context);
      playAudiobook(context, b);
    } catch (e) {
      if (mounted) toast(context, 'Could not add: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Scaffold(
      appBar: AppBar(title: AppTitle('New audiobook')),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 40), children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          GestureDetector(
            onTap: () async {
              final f = await FilePicker.pickFiles(type: FileType.image);
              final path = f.firstOrNull?.path;
              if (path != null) setState(() => _coverFile = path);
            },
            child: SizedBox(
              width: 120,
              child: AspectRatio(
                aspectRatio: 1,
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(color: t.raised, borderRadius: BorderRadius.circular(t.zen ? 14 : t.radius + 2), border: t.zen ? null : Border.all(color: t.line)),
                  child: _coverFile != null
                      ? Image.file(File(_coverFile!), fit: BoxFit.cover)
                      : (_coverUrl != null
                          ? NetImage(_coverUrl!)
                          : Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.add_photo_alternate_outlined, color: t.muted), const SizedBox(height: 4), Label('Cover', size: 9)]))),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Label('${_files.length} file${_files.length == 1 ? '' : 's'}', color: t.accent),
              const SizedBox(height: 8),
              if (_looking)
                Row(children: [
                  const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5)),
                  const SizedBox(width: 8),
                  Flexible(child: Text('Looking up book info…', style: TextStyle(color: t.muted, fontSize: 13))),
                ])
              else if (_match != null)
                Text('Filled in from ${_match!.source}. Not the right book? Search again.', style: TextStyle(color: t.muted, fontSize: 13, height: 1.35))
              else
                Text('No catalogue match for the file names. Search, or type the details in.', style: TextStyle(color: t.muted, fontSize: 13, height: 1.35)),
              const SizedBox(height: 10),
              ToolButton(Icons.search_sharp, label: 'Search info', size: 36, onTap: _search),
            ]),
          ),
        ]),
        const SizedBox(height: 20),
        TextField(controller: _title, decoration: const InputDecoration(labelText: 'Title')),
        const SizedBox(height: 8),
        TextField(controller: _author, decoration: const InputDecoration(labelText: 'Author')),
        const SizedBox(height: 8),
        TextField(controller: _desc, maxLines: 4, decoration: const InputDecoration(labelText: 'Description')),
        const SectionHeader('', 'The book · optional', padding: EdgeInsets.fromLTRB(0, 24, 0, 8)),
        Panel(
          padding: const EdgeInsets.all(14),
          child: _book == null
              ? Row(children: [
                  Icon(Icons.menu_book_outlined, color: t.muted),
                  const SizedBox(width: 12),
                  Expanded(child: Text('Attach the ebook to read along while it narrates.', style: TextStyle(color: t.muted, fontSize: 13, height: 1.35))),
                  const SizedBox(width: 8),
                  ToolButton(Icons.add_sharp, label: 'Attach', size: 36, onTap: () async {
                    final b = await pickBookForAudio(context, query: _title.text);
                    if (b != null) setState(() => _book = b);
                  }),
                ])
              : Row(children: [
                  SizedBox(width: 40, child: Cover(_book!)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_book!.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                      Label('Read along enabled', color: t.accent, size: 9),
                    ]),
                  ),
                  IconButton(onPressed: () => setState(() => _book = null), icon: Icon(Icons.close_sharp, color: t.muted)),
                ]),
        ),
        SectionHeader('', 'Chapters · drag to reorder', padding: const EdgeInsets.fromLTRB(0, 24, 0, 8)),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: _files.length,
          onReorderItem: (a, b) => setState(() => _files.insert(b, _files.removeAt(a))),
          itemBuilder: (_, i) => Container(
            key: ValueKey(_files[i].path),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.line))),
            child: Row(children: [
              SizedBox(width: 34, child: Label(pad(i + 1), color: t.accent)),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(cleanTrackTitle(_files[i].name), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500)),
                  Text(_files[i].name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.muted, fontSize: 11.5)),
                ]),
              ),
              ReorderableDragStartListener(index: i, child: Padding(padding: const EdgeInsets.all(8), child: Icon(Icons.drag_handle_sharp, color: t.muted))),
            ]),
          ),
        ),
        const SizedBox(height: 20),
        ValueListenableBuilder<double?>(
          valueListenable: AudioLibrary.i.importing,
          builder: (context, p, _) => Column(children: [
            if (p != null) ...[
              LinearProgressIndicator(value: p),
              const SizedBox(height: 6),
              Label('Copying files · ${(p * 100).round()}%'),
              const SizedBox(height: 10),
            ],
            PrimaryButton(_saving ? 'Adding…' : 'Add to shelf & play', icon: Icons.headphones_outlined, expand: true, onTap: _saving ? null : _save),
          ]),
        ),
        const SizedBox(height: 10),
        Text('Files are copied into Alexandria so they keep working even if the originals move.', style: TextStyle(color: t.muted, fontSize: 12.5)),
      ]),
    );
  }
}
