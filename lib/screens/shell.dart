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

/// (industrial icon, label, zen icon, zen label)
const _tabs = [
  (Icons.grid_view_sharp, 'Library', Icons.auto_stories_outlined, 'Library'),
  (Icons.travel_explore_sharp, 'Books', Icons.explore_outlined, 'Books'),
  (Icons.headphones_sharp, 'Audio', Icons.headphones_outlined, 'Audio'),
  (Icons.podcasts_sharp, 'Podcast', Icons.podcasts_outlined, 'Podcasts'),
  (Icons.tune_sharp, 'Config', Icons.settings_outlined, 'Settings'),
];

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

  void _select(int i) {
    haptic();
    shellTab.value = i;
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final pages = DotGrid(
      // On a big window each tab keeps to a centred column; settings, a list of rows, to a narrower one.
      child: IndexedStack(index: _tab, children: const [
        PageWidth(max: 1240, child: LibraryScreen()),
        PageWidth(max: 1240, child: DiscoverScreen()),
        PageWidth(max: 1240, child: AudiobooksScreen()),
        PageWidth(max: 1240, child: PodcastsScreen()),
        PageWidth(child: SettingsScreen()),
      ]),
    );
    // The side rail (see [NavFrame]) stands in for the bottom bar.
    if (NavFrame.shown(context)) {
      return Scaffold(body: Column(children: [Expanded(child: pages), const MiniPlayer()]));
    }
    return Scaffold(
      body: pages,
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
                    child: Tap(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _select(i),
                      child: t.zen ? _zenItem(t, i, _tab == i) : _item(t, i),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      ]),
    );
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

Widget _zenItem(Tokens t, int i, bool on) {
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

/// On a wide window, the tabs as a rail down the left edge of every page, not
/// just the home screen, so you can jump between sections from anywhere.
/// Wraps the app's navigator (see `MaterialApp.builder`).
class NavFrame extends StatelessWidget {
  const NavFrame({super.key, required this.navigator, required this.child});

  final GlobalKey<NavigatorState> navigator;
  final Widget child;

  /// Wider than this (a desktop window, a tablet in landscape) the tabs move to the rail.
  static const breakpoint = 840.0;
  static const width = 88.0;

  /// Screens that want the whole window (the reader) raise this while they're open.
  static final hidden = ValueNotifier<int>(0);

  /// Whether the rail is showing beside the page at [context].
  static bool shown(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_RailShown>()?.on ?? false;

  void _select(int i) {
    haptic();
    // Back to the home screen, on the tab asked for.
    navigator.currentState?.popUntil((r) => r.isFirst);
    shellTab.value = i;
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return ValueListenableBuilder<int>(
      valueListenable: hidden,
      builder: (context, h, _) {
        final on = mq.size.width >= breakpoint && h == 0;
        final w = on ? width : 0.0;
        // The tree keeps one shape either way, so the navigator inside never loses its pages.
        return Row(children: [
          SizedBox(width: w, child: on ? _rail(context) : null),
          Expanded(
            child: MediaQuery(
              // Pages that size things from the screen width see the space beside the rail.
              data: mq.copyWith(size: Size(mq.size.width - w, mq.size.height)),
              child: _RailShown(on: on, child: child),
            ),
          ),
        ]);
      },
    );
  }

  Widget _rail(BuildContext context) {
    final t = Tokens.of(context);
    return Material(
      color: t.zen ? t.surface : t.bg,
      child: Container(
        decoration: BoxDecoration(border: t.zen ? null : Border(right: BorderSide(color: t.line))),
        child: SafeArea(
          right: false,
          child: ValueListenableBuilder<int>(
            valueListenable: shellTab,
            builder: (context, tab, _) => Column(children: [
              const SizedBox(height: 20),
              for (var i = 0; i < _tabs.length; i++)
                Tap(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _select(i),
                  child: SizedBox(height: 72, child: t.zen ? _zenItem(t, i, tab == i) : _railItem(t, i, tab == i)),
                ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _railItem(Tokens t, int i, bool on) {
    return Stack(fit: StackFit.expand, alignment: Alignment.center, children: [
      AnimatedPositioned(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        left: 0,
        width: 2,
        height: on ? 28 : 0,
        child: Container(color: t.accent),
      ),
      Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(_tabs[i].$1, size: 21, color: on ? t.ink : t.muted),
        const SizedBox(height: 5),
        Label(_tabs[i].$2, size: 9.5, color: on ? t.ink : t.muted, weight: FontWeight.w600),
      ]),
    ]);
  }
}

class _RailShown extends InheritedWidget {
  const _RailShown({required this.on, required super.child});
  final bool on;

  @override
  bool updateShouldNotify(_RailShown old) => old.on != on;
}
