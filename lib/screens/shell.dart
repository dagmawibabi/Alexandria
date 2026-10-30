import 'package:material_ui/material_ui.dart';

import '../core/theme.dart';
import '../core/ui.dart';
import 'audiobooks_screen.dart';
import 'discover_screen.dart';
import 'library_screen.dart';
import 'player_screen.dart';
import 'podcasts_view.dart';
import 'settings_screen.dart';

/// Which tab is showing, so other screens can send you to one.
final shellTab = ValueNotifier<int>(0);

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int get _tab => shellTab.value;

  @override
  void initState() {
    super.initState();
    shellTab.addListener(_changed);
  }

  @override
  void dispose() {
    shellTab.removeListener(_changed);
    super.dispose();
  }

  void _changed() => setState(() {});

  /// (industrial icon, label, zen icon, zen label)
  static const _tabs = [
    (Icons.grid_view_sharp, 'Library', Icons.auto_stories_outlined, 'Library'),
    (Icons.travel_explore_sharp, 'Books', Icons.explore_outlined, 'Books'),
    (Icons.headphones_sharp, 'Audio', Icons.headphones_outlined, 'Audio'),
    (Icons.podcasts_sharp, 'Podcast', Icons.podcasts_outlined, 'Podcasts'),
    (Icons.tune_sharp, 'Config', Icons.settings_outlined, 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Scaffold(
      body: DotGrid(
        child: IndexedStack(index: _tab, children: const [LibraryScreen(), DiscoverScreen(), AudiobooksScreen(), PodcastsScreen(), SettingsScreen()]),
      ),
      bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [
        const MiniPlayer(),
        Container(
          decoration: BoxDecoration(color: t.zen ? t.surface : t.bg, border: t.zen ? null : Border(top: BorderSide(color: t.line))),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: t.zen ? 66 : 62,
              child: Row(children: [
                for (var i = 0; i < _tabs.length; i++)
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        haptic();
                        shellTab.value = i;
                      },
                      child: t.zen ? _zenItem(t, i) : _item(t, i),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _zenItem(Tokens t, int i) {
    final on = _tab == i;
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(color: on ? t.accent.withValues(alpha: .14) : Colors.transparent, borderRadius: BorderRadius.circular(10)),
        child: Icon(_tabs[i].$3, size: 22, color: on ? t.accent : t.muted),
      ),
      const SizedBox(height: 4),
      Text(_tabs[i].$4, maxLines: 1, style: TextStyle(fontSize: 11.5, color: on ? t.ink : t.muted, fontWeight: on ? FontWeight.w600 : FontWeight.w500)),
    ]);
  }

  Widget _item(Tokens t, int i) {
    return Stack(alignment: Alignment.center, children: [
      AnimatedPositioned(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        top: 0,
        height: 2,
        width: _tab == i ? 28 : 0,
        child: Container(color: t.accent),
      ),
      Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(_tabs[i].$1, size: 21, color: _tab == i ? t.ink : t.muted),
        const SizedBox(height: 5),
        Label(_tabs[i].$2, size: 9.5, color: _tab == i ? t.ink : t.muted, weight: FontWeight.w600),
      ]),
    ]);
  }
}
