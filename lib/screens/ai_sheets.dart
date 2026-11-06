import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:omni_ai/omni_ai.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../core/settings.dart';
import '../core/search_box.dart';
import '../core/theme.dart';
import '../core/ui.dart';
import '../models/book.dart';
import '../services/ai.dart';
import '../core/skeleton.dart';

/// Makes sure an AI key exists; offers to add one if not.
Future<bool> ensureAi(BuildContext context) async {
  await Ai.ready;
  if (Ai.configured) return true;
  if (!context.mounted) return false;
  await showSheet(context, builder: (ctx) => const Padding(padding: EdgeInsets.fromLTRB(20, 8, 20, 24), child: AiKeysPanel(intro: true)));
  return Ai.configured;
}

/// Key entry for Google AI Studio and Vercel AI Gateway, via omni_ai's key store.
class AiKeysPanel extends StatefulWidget {
  const AiKeysPanel({super.key, this.intro = false});
  final bool intro;

  @override
  State<AiKeysPanel> createState() => _AiKeysPanelState();
}

class _AiKeysPanelState extends State<AiKeysPanel> {
  static const _info = {
    'google': ('Google AI Studio', 'Gemini models. Free tier available.', 'https://aistudio.google.com/apikey'),
    'gateway': ('Vercel AI Gateway', 'One key for GPT, Claude, Gemini, Grok…', 'https://vercel.com/ai-gateway'),
  };
  final _ctl = {for (final k in Ai.providers) k: TextEditingController()};
  final _status = <String, String>{};

  bool _has(String id) => id == 'google' ? Ai.omni.google.isConfigured : Ai.omni.gateway.isConfigured;

  Future<void> _save(String id) async {
    final key = _ctl[id]!.text.trim();
    if (key.isEmpty) return;
    setState(() => _status[id] = 'Checking…');
    await Ai.omni.setApiKey(id, key);
    final problem = await Ai.omni.verifyKey(id);
    if (!mounted) return;
    setState(() => _status[id] = problem == null ? 'Connected' : 'Error: $problem');
    if (problem == null) {
      _ctl[id]!.clear();
      if (!Settings.i.aiModel.startsWith('$id:')) Settings.i.aiModel = id == 'google' ? 'google:gemini-2.5-flash' : 'gateway:google/gemini-2.5-flash';
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (widget.intro) ...[
        Label('AI · offline', color: t.accent),
        const SizedBox(height: 8),
        const Text('Connect a model', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text('Explanations, book chat and recaps run on your own key. It is stored in the device keychain and only sent to the provider.',
            style: TextStyle(color: t.muted, height: 1.45)),
        const SizedBox(height: 18),
      ],
      for (final id in Ai.providers) ...[
        Panel(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: _has(id) ? const Color(0xFF00C27A) : t.line)),
              const SizedBox(width: 8),
              Expanded(child: Text(_info[id]!.$1, style: const TextStyle(fontWeight: FontWeight.w600))),
              GestureDetector(onTap: () => launchUrlString(_info[id]!.$3, mode: LaunchMode.externalApplication), child: Label('Get key ↗', color: t.accent)),
            ]),
            const SizedBox(height: 4),
            Text(_info[id]!.$2, style: TextStyle(color: t.muted, fontSize: 12.5)),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _ctl[id],
                  obscureText: true,
                  decoration: InputDecoration(hintText: _has(id) ? '•••••••• saved — paste to replace' : 'Paste API key'),
                  onSubmitted: (_) => _save(id),
                ),
              ),
              const SizedBox(width: 8),
              ToolButton(Icons.check_sharp, active: true, onTap: () => _save(id)),
              if (_has(id)) ...[
                const SizedBox(width: 8),
                ToolButton(Icons.close_sharp, tooltip: 'Remove key', onTap: () async {
                  await Ai.omni.setApiKey(id, null);
                  setState(() => _status[id] = 'Removed');
                }),
              ],
            ]),
            if (_status[id] != null) Padding(padding: const EdgeInsets.only(top: 8), child: Label(_status[id]!, color: _status[id] == 'Connected' ? const Color(0xFF00A86B) : t.muted)),
          ]),
        ),
        const SizedBox(height: 10),
      ],
    ]);
  }
}

/// Model chooser: presets plus the full omni_ai catalog.
Future<void> pickModel(BuildContext context) async {
  await showSheet(context, builder: (ctx) {
    final t = Tokens.of(ctx);
    return StatefulBuilder(builder: (ctx, setS) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Label('Model', color: t.accent),
          const SizedBox(height: 12),
          for (final m in Ai.presetModels)
            _modelRow(ctx, m.$1, m.$2, () => setS(() {})),
          const SizedBox(height: 10),
          PrimaryButton('Browse full catalog', ghost: true, icon: Icons.list_sharp, expand: true, onTap: () async {
            Navigator.pop(ctx);
            await _catalog(context);
          }),
        ]),
      );
    });
  });
}

Widget _modelRow(BuildContext ctx, String id, String name, VoidCallback changed) {
  final t = Tokens.of(ctx);
  final selected = Settings.i.aiModel == id;
  final provider = id.split(':').first;
  final ok = provider == 'google' ? Ai.omni.google.isConfigured : Ai.omni.gateway.isConfigured;
  return GestureDetector(
    onTap: () {
      haptic();
      Settings.i.aiModel = id;
      changed();
    },
    child: Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(color: selected ? t.ink : t.raised, borderRadius: t.br, border: t.zen ? null : Border.all(color: selected ? t.ink : t.line)),
      child: Row(children: [
        Expanded(child: Text(name, style: TextStyle(color: selected ? t.bg : t.ink, fontWeight: FontWeight.w600))),
        Label(ok ? provider : '$provider · no key', color: selected ? t.bg.withValues(alpha: .7) : t.muted),
      ]),
    ),
  );
}

Future<void> _catalog(BuildContext context) async {
  await showSheet(context, scroll: false, builder: (_) => const _CatalogSheet());
}

class _CatalogSheet extends StatefulWidget {
  const _CatalogSheet();

  @override
  State<_CatalogSheet> createState() => _CatalogSheetState();
}

// The search lives in State: showSheet's builder runs again whenever the keyboard
// opens or closes, which would lose anything kept there and reshuffle the list.
class _CatalogSheetState extends State<_CatalogSheet> {
  final _loading = Ai.loadCatalog();
  var _q = '';

  String get _emptyText {
    if (!Ai.configured) return 'Add a key to see models';
    if (_q.trim().isNotEmpty) return 'No models match';
    return 'Could not load models. Check your key and connection.';
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return FutureBuilder(
      future: _loading,
      builder: (ctx, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(padding: EdgeInsets.fromLTRB(20, 8, 20, 0), child: Column(children: [Shimmer(child: Bone(height: 44)), SizedBox(height: 10), SkeletonRows(count: 7, art: null, dividers: false)]));
        }
        final models = Ai.omni.catalog
            .search(_q, type: ModelType.text)
            .where((m) => (m.provider == 'google' && Ai.omni.google.isConfigured) || (m.provider == 'gateway' && Ai.omni.gateway.isConfigured))
            .take(120)
            .toList();
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Column(children: [
            SearchBox(historyKey: 'ai-models', decoration: const InputDecoration(hintText: 'Search models', prefixIcon: Icon(Icons.search_sharp, size: 18)), onChanged: (v) => setState(() => _q = v)),
            const SizedBox(height: 10),
            if (models.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Label(_emptyText)),
            Expanded(
              child: ListView.builder(
                itemCount: models.length,
                itemBuilder: (_, i) {
                  final m = models[i];
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(m.name, style: TextStyle(color: t.ink, fontWeight: Settings.i.aiModel == m.id ? FontWeight.w700 : FontWeight.w500)),
                    subtitle: Text(m.id, style: mono(ctx, size: 10, spacing: 0)),
                    trailing: Settings.i.aiModel == m.id ? Icon(Icons.check_sharp, color: t.accent) : null,
                    onTap: () {
                      Settings.i.aiModel = m.id;
                      Navigator.pop(ctx);
                    },
                  );
                },
              ),
            ),
          ]),
        );
      },
    );
  }
}

/// A sheet that streams one AI answer, with optional mode switching.
Future<void> showAiStream(
  BuildContext context, {
  required String title,
  String? subtitle,
  required Stream<String> Function() make,
  Book? book,
  String? passage,
  List<(String, String)> modes = const [],
  Stream<String> Function(String mode)? makeMode,
  String? initialMode,
}) {
  return showSheet(context, scroll: false, builder: (ctx) => _AiStreamSheet(title: title, subtitle: subtitle, make: make, book: book, passage: passage, modes: modes, makeMode: makeMode, initialMode: initialMode));
}

class _AiStreamSheet extends StatefulWidget {
  const _AiStreamSheet({required this.title, this.subtitle, required this.make, this.book, this.passage, this.modes = const [], this.makeMode, this.initialMode});
  final String title;
  final String? subtitle;
  final Stream<String> Function() make;
  final Book? book;
  final String? passage;
  final List<(String, String)> modes;
  final Stream<String> Function(String mode)? makeMode;
  final String? initialMode;

  @override
  State<_AiStreamSheet> createState() => _AiStreamSheetState();
}

class _AiStreamSheetState extends State<_AiStreamSheet> {
  StreamSubscription<String>? _sub;
  String _text = '';
  String? _error;
  bool _done = false;
  late String? _mode = widget.initialMode;

  @override
  void initState() {
    super.initState();
    _run();
  }

  void _run() {
    _sub?.cancel();
    setState(() {
      _text = '';
      _error = null;
      _done = false;
    });
    final s = (_mode != null && widget.makeMode != null) ? widget.makeMode!(_mode!) : widget.make();
    _sub = s.listen(
      (v) => setState(() => _text = v),
      onError: (e) => setState(() {
        _error = '$e';
        _done = true;
      }),
      onDone: () => setState(() => _done = true),
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.auto_awesome, size: 14, color: t.accent),
          const SizedBox(width: 8),
          Label(widget.title, color: t.ink, weight: FontWeight.w700),
          const Spacer(),
          Label(Ai.model.split(':').last.split('/').last, size: 9),
        ]),
        if (widget.subtitle != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.only(left: 12),
            decoration: BoxDecoration(border: Border(left: BorderSide(color: t.accent, width: 2))),
            child: Text(widget.subtitle!, maxLines: 4, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.muted, fontStyle: FontStyle.italic, height: 1.4)),
          ),
        ],
        if (widget.modes.isNotEmpty) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 34,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (final m in widget.modes)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Tag(m.$2, filled: _mode == m.$1, onTap: () {
                    _mode = m.$1;
                    _run();
                  }),
                ),
            ]),
          ),
        ],
        const SizedBox(height: 12),
        Flexible(
          child: SingleChildScrollView(
            child: _error != null
                ? Text(_error!, style: const TextStyle(color: Color(0xFFE5243B)))
                : _text.isEmpty
                    ? Padding(padding: const EdgeInsets.symmetric(vertical: 24), child: Row(children: [const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5)), const SizedBox(width: 12), Label('Thinking')]))
                    : MarkdownLite(_text),
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          ToolButton(Icons.refresh_sharp, onTap: _run, tooltip: 'Regenerate'),
          const SizedBox(width: 8),
          ToolButton(Icons.copy_sharp, onTap: _text.isEmpty
              ? null
              : () {
                  Clipboard.setData(ClipboardData(text: _text));
                  toast(context, 'Copied');
                }),
          const Spacer(),
          if (widget.book != null)
            ToolButton(Icons.forum_outlined, label: 'Follow up', onTap: !_done
                ? null
                : () {
                    Navigator.pop(context);
                    openAiChat(context, widget.book!, passage: widget.passage, seed: [
                      if (widget.subtitle != null) Message.user('About: "${widget.subtitle}"'),
                      Message.assistant(_text),
                    ]);
                  }),
        ]),
      ]),
    );
  }
}

/// Minimal Markdown: headings, bullets, numbered lists, **bold**, *italic*, `code`.
class MarkdownLite extends StatelessWidget {
  const MarkdownLite(this.text, {super.key, this.color, this.size = 15});
  final String text;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final base = TextStyle(color: color ?? t.ink, fontSize: size, height: 1.5);
    final lines = text.split('\n');
    final children = <Widget>[];
    for (final raw in lines) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) {
        children.add(const SizedBox(height: 8));
        continue;
      }
      final h = RegExp(r'^(#{1,4})\s+(.*)').firstMatch(line);
      final bullet = RegExp(r'^\s*[-*•]\s+(.*)').firstMatch(line);
      final num = RegExp(r'^\s*(\d+)[.)]\s+(.*)').firstMatch(line);
      if (h != null) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 4),
          child: Text.rich(_inline(h.group(2)!, base.copyWith(fontWeight: FontWeight.w700, fontSize: size + (5 - h.group(1)!.length) * 1.5), t)),
        ));
      } else if (bullet != null || num != null) {
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 22, child: Text(num != null ? '${num.group(1)}.' : '■', style: base.copyWith(color: t.accent, fontSize: num != null ? size : size * .55, height: num != null ? 1.5 : 2.6))),
            Expanded(child: Text.rich(_inline((bullet?.group(1) ?? num!.group(2))!, base, t))),
          ]),
        ));
      } else {
        children.add(Text.rich(_inline(line, base, t)));
      }
    }
    return SelectionArea(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children));
  }

  TextSpan _inline(String s, TextStyle base, Tokens t) {
    final spans = <TextSpan>[];
    final re = RegExp(r'(\*\*[^*]+\*\*|\*[^*]+\*|`[^`]+`)');
    var last = 0;
    for (final m in re.allMatches(s)) {
      if (m.start > last) spans.add(TextSpan(text: s.substring(last, m.start)));
      final tok = m.group(0)!;
      if (tok.startsWith('**')) {
        spans.add(TextSpan(text: tok.substring(2, tok.length - 2), style: const TextStyle(fontWeight: FontWeight.w700)));
      } else if (tok.startsWith('`')) {
        spans.add(TextSpan(text: tok.substring(1, tok.length - 1), style: TextStyle(fontFamily: 'monospace', backgroundColor: t.line.withValues(alpha: .5))));
      } else {
        spans.add(TextSpan(text: tok.substring(1, tok.length - 1), style: const TextStyle(fontStyle: FontStyle.italic)));
      }
      last = m.end;
    }
    if (last < s.length) spans.add(TextSpan(text: s.substring(last)));
    return TextSpan(style: base, children: spans);
  }
}

Future<void> openAiChat(BuildContext context, Book book, {String? passage, List<Message> seed = const []}) async {
  if (!await ensureAi(context)) return;
  if (!context.mounted) return;
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => AiChatScreen(book: book, passage: passage, seed: seed)));
}

class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key, required this.book, this.passage, this.seed = const []});
  final Book book;
  final String? passage;
  final List<Message> seed;

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  late final List<Message> _history = [...widget.seed];
  late final List<(bool, String)> _shown = [
    for (final m in widget.seed) (m.role == Role.user, m.text),
  ];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  StreamSubscription<String>? _sub;
  bool _busy = false;

  static const _suggest = [
    'What is this book, and why does it matter?',
    'Who are the main characters so far?',
    'Summarise what I have read',
    'What themes should I watch for?',
    'Explain the historical context',
  ];

  void _send(String text) {
    if (text.trim().isEmpty || _busy) return;
    _input.clear();
    _history.add(Message.user(text));
    setState(() {
      _shown.add((true, text));
      _shown.add((false, ''));
      _busy = true;
    });
    var answer = '';
    _sub = Ai.chat(widget.book, _history, passage: widget.passage).listen(
      (v) {
        answer = v;
        setState(() => _shown[_shown.length - 1] = (false, v));
        _toEnd();
      },
      onError: (e) => setState(() {
        _shown[_shown.length - 1] = (false, '⚠ $e');
        _busy = false;
      }),
      onDone: () => setState(() {
        _history.add(Message.assistant(answer));
        _busy = false;
      }),
    );
  }

  void _toEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Label('Companion · ${Ai.model.split(':').last}', color: t.accent, size: 9),
          const SizedBox(height: 2),
          Text(widget.book.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ]),
        actions: [IconButton(onPressed: () => pickModel(context).then((_) => setState(() {})), icon: const Icon(Icons.memory_sharp))],
      ),
      body: Column(children: [
        Expanded(
          child: ListView(controller: _scroll, padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
            if (widget.passage != null)
              Panel(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Label('Context'),
                  const SizedBox(height: 6),
                  Text(widget.passage!, maxLines: 6, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.muted, fontStyle: FontStyle.italic)),
                ]),
              ),
            if (_shown.isEmpty) ...[
              const SizedBox(height: 30),
              Text('Ask anything about\n${widget.book.title}', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, height: 1.1, letterSpacing: -.6)),
              const SizedBox(height: 8),
              Label(Settings.i.aiSpoilerGuard ? 'Spoiler guard on · ${(widget.book.progress * 100).round()}% read' : 'Spoiler guard off'),
              const SizedBox(height: 20),
              for (final s in _suggest)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Panel(
                    onTap: () => _send(s),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(children: [Expanded(child: Text(s)), Icon(Icons.north_east_sharp, size: 16, color: t.accent)]),
                  ),
                ),
            ],
            for (final (user, text) in _shown)
              Align(
                alignment: user ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.only(top: 10),
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * (user ? .78 : .92)),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: user ? t.ink : t.surface,
                    borderRadius: t.br,
                    border: t.zen ? null : Border.all(color: user ? t.ink : t.line),
                  ),
                  child: user
                      ? Text(text, style: TextStyle(color: t.bg))
                      : text.isEmpty
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5))
                          : MarkdownLite(text),
                ),
              ),
          ]),
        ),
        Container(
          padding: EdgeInsets.fromLTRB(12, 10, 12, 10 + MediaQuery.of(context).padding.bottom),
          decoration: BoxDecoration(color: t.bg, border: t.zen ? null : Border(top: BorderSide(color: t.line))),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                decoration: const InputDecoration(hintText: 'Ask about the book…'),
                onSubmitted: _send,
              ),
            ),
            const SizedBox(width: 8),
            ToolButton(_busy ? Icons.stop_sharp : Icons.arrow_upward_sharp, active: true, onTap: () {
              if (_busy) {
                _sub?.cancel();
                setState(() => _busy = false);
              } else {
                _send(_input.text);
              }
            }),
          ]),
        ),
      ]),
    );
  }
}
