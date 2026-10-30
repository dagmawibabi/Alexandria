import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../services/storage.dart';
import 'theme.dart';
import 'ui.dart';

/// What's been searched for, per search bar, newest first. Only on this device.
class SearchHistory extends ChangeNotifier {
  SearchHistory._();
  static final SearchHistory i = SearchHistory._();

  static const _keep = 12;

  final Map<String, List<String>> _all = {};

  Future<void> load() async {
    final j = await Storage.readJson('search_history');
    if (j is Map) mergeBackup(j, save: false);
  }

  Map<String, dynamic> toJson() => {
    for (final e in _all.entries)
      if (e.value.isNotEmpty) e.key: e.value,
  };

  /// Adds a backup's searches after the ones here.
  void mergeBackup(dynamic j, {bool save = true}) {
    if (j is! Map) return;
    for (final e in j.entries) {
      if (e.value is! List) continue;
      final mine = _all['${e.key}'] ?? const <String>[];
      _all['${e.key}'] = {...mine, ...(e.value as List).whereType<String>()}.take(_keep).toList();
    }
    if (save) _changed();
  }

  List<String> of(String key) => _all[key] ?? const [];

  void add(String key, String text) {
    final t = text.trim();
    if (t.length < 2) return;
    final list = [...of(key)]..removeWhere((x) => x.toLowerCase() == t.toLowerCase());
    list.insert(0, t);
    _all[key] = list.take(_keep).toList();
    _changed();
  }

  void remove(String key, String text) {
    _all[key] = [...of(key)]..remove(text);
    _changed();
  }

  void clear(String key) {
    _all.remove(key);
    _changed();
  }

  Timer? _pending;

  void _changed() {
    _pending?.cancel();
    _pending = Timer(const Duration(milliseconds: 400), () => Storage.writeJson('search_history', toJson()));
    notifyListeners();
  }
}

/// A search field that remembers. Recent searches appear under it while it has
/// focus, narrowing as you type; each can be removed, or all cleared.
class SearchBox extends StatefulWidget {
  const SearchBox({super.key, required this.historyKey, this.controller, this.decoration, this.onChanged, this.onSubmitted, this.autofocus = false, this.textInputAction = TextInputAction.search});

  /// Which bar this is; each keeps its own history.
  final String historyKey;
  final TextEditingController? controller;
  final InputDecoration? decoration;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final TextInputAction textInputAction;

  @override
  State<SearchBox> createState() => _SearchBoxState();
}

class _SearchBoxState extends State<SearchBox> {
  final _focus = FocusNode();
  late final TextEditingController _c = widget.controller ?? TextEditingController();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
  }

  void _focusChanged() {
    // Filter-as-you-type bars have no search button, so leaving counts as searching.
    if (!_focus.hasFocus) SearchHistory.i.add(widget.historyKey, _c.text);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    final text = _c.text;
    final key = widget.historyKey;
    // Not while the tree is being torn down: that's no time to notify anyone.
    if (_focus.hasFocus) scheduleMicrotask(() => SearchHistory.i.add(key, text));
    _focus.removeListener(_focusChanged);
    _focus.dispose();
    if (widget.controller == null) _c.dispose();
    super.dispose();
  }

  void _pick(String text) {
    _c.text = text;
    _c.selection = TextSelection.collapsed(offset: text.length);
    widget.onChanged?.call(text);
    widget.onSubmitted?.call(text);
    SearchHistory.i.add(widget.historyKey, text);
    _focus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _c,
          focusNode: _focus,
          autofocus: widget.autofocus,
          textInputAction: widget.textInputAction,
          decoration: widget.decoration,
          onTapOutside: (_) => _focus.unfocus(),
          onChanged: (v) {
            widget.onChanged?.call(v);
            setState(() {});
          },
          onSubmitted: (v) {
            SearchHistory.i.add(widget.historyKey, v);
            widget.onSubmitted?.call(v);
          },
        ),
        if (_focus.hasFocus)
          ListenableBuilder(
            listenable: SearchHistory.i,
            builder: (context, _) {
              final typed = _c.text.trim().toLowerCase();
              final items = SearchHistory.i.of(widget.historyKey).where((x) => x.toLowerCase() != typed && (typed.isEmpty || x.toLowerCase().contains(typed))).take(6).toList();
              if (items.isEmpty) return const SizedBox.shrink();
              // Counts as part of the field, or tapping an entry would close the list first.
              return TextFieldTapRegion(
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Panel(
                    padding: const EdgeInsets.fromLTRB(12, 8, 2, 4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Expanded(child: Label('Recent', size: 9.5)),
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => SearchHistory.i.clear(widget.historyKey),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                child: Label('Clear', color: t.accent, weight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                        for (final s in items)
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _pick(s),
                            child: Row(
                              children: [
                                Icon(Icons.history_sharp, size: 17, color: t.muted),
                                const SizedBox(width: 10),
                                Expanded(child: Text(s, maxLines: 1, overflow: TextOverflow.ellipsis)),
                                IconButton(
                                  tooltip: 'Remove from history',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () => SearchHistory.i.remove(widget.historyKey, s),
                                  icon: Icon(Icons.close_sharp, size: 16, color: t.muted),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}
