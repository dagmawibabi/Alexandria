import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';

import '../core/settings.dart';
import '../core/theme.dart';
import '../core/ui.dart';
import '../services/stat_widgets.dart';
import 'quote_card.dart';

void openStatWidgets(BuildContext context) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const StatWidgetsScreen()));

/// Design a home-screen widget for each kind of stat, and add it to the home screen.
class StatWidgetsScreen extends StatefulWidget {
  const StatWidgetsScreen({super.key});

  @override
  State<StatWidgetsScreen> createState() => _StatWidgetsScreenState();
}

class _StatWidgetsScreenState extends State<StatWidgetsScreen> {
  String _kind = 'all';
  late WidgetStyle _style = WidgetStyle.of(_kind);

  /// Every change is saved and shown at once; the home screen catches up on leaving.
  void _change(void Function(WidgetStyle) f) {
    setState(() => f(_style));
    Settings.i.setWidgetStyle(_kind, _style.toJson());
  }

  void _pickFont(String font) {
    _change((s) => s.font = font);
    // The preview redraws once the font has arrived.
    GoogleFonts.pendingFonts([GoogleFonts.getFont(font)]).then((_) {
      if (mounted) setState(() {});
    }).catchError((_) {});
  }

  @override
  void initState() {
    super.initState();
    _pickFontQuietly();
  }

  void _pickFontQuietly() {
    GoogleFonts.pendingFonts([GoogleFonts.getFont(_style.font)]).then((_) {
      if (mounted) setState(() {});
    }).catchError((_) {});
  }

  @override
  void dispose() {
    StatWidgets.i.refresh();
    super.dispose();
  }

  Future<void> _add() async {
    final ok = await StatWidgets.i.pin(_kind);
    if (!mounted) return;
    toast(context, ok ? 'Confirm on your home screen' : 'Hold your home screen, tap Widgets, and find Alexandria');
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final st = _style;
    final size = StatWidgets.defaultSize(_kind);
    return Scaffold(
      appBar: AppBar(title: AppTitle('Home-screen widgets')),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 40), children: [
        Segmented<String>(
          values: widgetKinds,
          labels: [for (final k in widgetKinds) widgetKindNames[k]!],
          value: _kind,
          onChanged: (v) {
            setState(() {
              _kind = v;
              _style = WidgetStyle.of(v);
            });
            _pickFontQuietly();
          },
        ),
        const SizedBox(height: 16),
        // A mid-grey backdrop so light and dark widgets, and transparency, both show.
        Container(
          padding: const EdgeInsets.symmetric(vertical: 22),
          decoration: BoxDecoration(
            borderRadius: t.br,
            gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF5B6B8C), Color(0xFF8C6B7A)]),
          ),
          child: Center(
            child: LayoutBuilder(builder: (context, c) {
              final scale = ((c.maxWidth - 32) / size.width).clamp(.4, 1.0);
              return CustomPaint(
                size: size * scale.toDouble(),
                painter: _ScaledPreview(StatWidgetPainter(kind: _kind, data: WidgetData.current(), style: st), scale.toDouble()),
              );
            }),
          ),
        ),
        const SizedBox(height: 12),
        PrimaryButton('Add to home screen', icon: Icons.add_to_home_screen_sharp, expand: true, onTap: _add),
        const SizedBox(height: 6),
        Text('Resize it on your home screen and it redraws to fit. Numbers refresh when you use the app or leave it, so they can be behind if it hasn\'t been opened today.',
            style: TextStyle(color: t.muted, fontSize: 12.5, height: 1.4)),

        const SectionHeader('', 'Font', padding: EdgeInsets.fromLTRB(0, 24, 0, 10)),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final f in {'Inter', ...uiFonts, ...readerFonts}) Tag(f, filled: st.font == f, onTap: () => _pickFont(f)),
        ]),

        const SectionHeader('', 'Colours', padding: EdgeInsets.fromLTRB(0, 24, 0, 10)),
        CardColorPicker(label: 'Background', resetLabel: 'Default', value: st.background, onChanged: (c) => _change((s) => s.background = c)),
        const SizedBox(height: 14),
        CardColorPicker(label: 'Text', resetLabel: 'Automatic', value: st.text, onChanged: (c) => _change((s) => s.text = c)),
        const SizedBox(height: 14),
        CardColorPicker(label: 'Accent', resetLabel: 'App accent', value: st.accent, onChanged: (c) => _change((s) => s.accent = c)),

        const SectionHeader('', 'Shape', padding: EdgeInsets.fromLTRB(0, 24, 0, 6)),
        SliderRow(label: 'Opacity', value: st.opacity, min: 0, max: 1, divisions: 20, format: (v) => '${(v * 100).round()}%', onChanged: (v) => _change((s) => s.opacity = v)),
        SliderRow(label: 'Corners', value: st.radius, min: 0, max: 40, divisions: 20, format: (v) => '${v.round()}', onChanged: (v) => _change((s) => s.radius = v)),

        const SectionHeader('', 'What it shows', padding: EdgeInsets.fromLTRB(0, 24, 0, 6)),
        ToggleRow(label: 'Title', value: st.showTitle, onChanged: (v) => _change((s) => s.showTitle = v)),
        ToggleRow(label: 'Daily goal bar', value: st.showGoal, onChanged: (v) => _change((s) => s.showGoal = v)),
        ToggleRow(label: 'This week', value: st.showWeek, onChanged: (v) => _change((s) => s.showWeek = v)),
        ToggleRow(label: 'Streak', value: st.showStreak, onChanged: (v) => _change((s) => s.showStreak = v)),
        ToggleRow(label: 'Finished count', value: st.showDone, onChanged: (v) => _change((s) => s.showDone = v)),
      ]),
    );
  }
}

class _ScaledPreview extends CustomPainter {
  _ScaledPreview(this.inner, this.scale);
  final StatWidgetPainter inner;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(scale);
    inner.paint(canvas, size / scale);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ScaledPreview old) => true;
}
