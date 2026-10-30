import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'theme.dart';
import 'ui.dart';

/// "#2D6BFF" from a colour.
String colorHex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// A colour from "#2D6BFF", "2d6bff" or "#26f"; null if it isn't one.
Color? parseHex(String text) {
  var s = text.trim().replaceFirst('#', '');
  if (s.length == 3) s = s.split('').map((c) => '$c$c').join();
  if (s.length != 6) return null;
  final v = int.tryParse(s, radix: 16);
  return v == null ? null : Color(0xFF000000 | v);
}

/// Pick any colour. Null if cancelled.
Future<Color?> showColorPicker(BuildContext context, {required Color initial, String title = 'Choose a colour'}) {
  return showSheet<Color>(context, builder: (_) => _Picker(initial: initial, title: title));
}

class _Picker extends StatefulWidget {
  const _Picker({required this.initial, required this.title});
  final Color initial;
  final String title;

  @override
  State<_Picker> createState() => _PickerState();
}

class _PickerState extends State<_Picker> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initial.withValues(alpha: 1));
  late final _hex = TextEditingController(text: colorHex(widget.initial));

  Color get _color => _hsv.toColor();

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _set(HSVColor v) {
    setState(() => _hsv = v);
    _hex.text = colorHex(v.toColor());
  }

  void _typed(String text) {
    final c = parseHex(text);
    if (c == null) return;
    // Keep the hue when a grey is typed, so the hue bar doesn't jump to red.
    final next = HSVColor.fromColor(c);
    setState(() => _hsv = next.saturation == 0 ? next.withHue(_hsv.hue) : next);
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final radius = BorderRadius.circular(t.zen ? 12 : t.radius + 2);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 14),
        // Saturation across, brightness down.
        LayoutBuilder(builder: (context, c) {
          const h = 190.0;
          final w = c.maxWidth;
          void at(Offset p) => _set(_hsv.withSaturation((p.dx / w).clamp(0.0, 1.0)).withValue(1 - (p.dy / h).clamp(0.0, 1.0)));
          return _Pad(
            onPoint: at,
            child: ClipRRect(
              borderRadius: radius,
              child: SizedBox(
                width: w,
                height: h,
                child: CustomPaint(painter: _SquarePainter(_hsv)),
              ),
            ),
          );
        }),
        const SizedBox(height: 14),
        LayoutBuilder(builder: (context, c) {
          final w = c.maxWidth;
          void at(Offset p) => _set(_hsv.withHue((p.dx / w).clamp(0.0, 1.0) * 359.9));
          return _Pad(onPoint: at, child: SizedBox(width: w, height: 30, child: CustomPaint(painter: _HuePainter(_hsv.hue))));
        }),
        const SizedBox(height: 16),
        Row(children: [
          Container(width: 48, height: 48, decoration: BoxDecoration(color: _color, borderRadius: radius, border: Border.all(color: t.line))),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _hex,
              onChanged: _typed,
              autocorrect: false,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[#0-9a-fA-F]')), LengthLimitingTextInputFormatter(7)],
              decoration: const InputDecoration(labelText: 'Hex'),
            ),
          ),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: PrimaryButton('Cancel', ghost: true, onTap: () => Navigator.pop(context))),
          const SizedBox(width: 10),
          Expanded(child: PrimaryButton('Use colour', onTap: () => Navigator.pop(context, _color))),
        ]),
      ]),
    );
  }
}

/// Follows a finger, and keeps it: dragging here must not drag the sheet away.
class _Pad extends StatelessWidget {
  const _Pad({required this.onPoint, required this.child});
  final ValueChanged<Offset> onPoint;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: {EagerGestureRecognizer: GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(EagerGestureRecognizer.new, (_) {})},
      child: Listener(
        onPointerDown: (e) => onPoint(e.localPosition),
        onPointerMove: (e) => onPoint(e.localPosition),
        child: child,
      ),
    );
  }
}

class _SquarePainter extends CustomPainter {
  _SquarePainter(this.hsv);
  final HSVColor hsv;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..shader = LinearGradient(colors: [Colors.white, HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor()]).createShader(rect));
    canvas.drawRect(rect, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black]).createShader(rect));
    final at = Offset(hsv.saturation * size.width, (1 - hsv.value) * size.height);
    canvas.drawCircle(at, 10, Paint()..color = hsv.toColor());
    canvas.drawCircle(
        at,
        10,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3);
    canvas.drawCircle(
        at,
        11.5,
        Paint()
          ..color = Colors.black.withValues(alpha: .4)
          ..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(_SquarePainter o) => o.hsv != hsv;
}

class _HuePainter extends CustomPainter {
  _HuePainter(this.hue);
  final double hue;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final colors = [for (var h = 0.0; h <= 360; h += 60) HSVColor.fromAHSV(1, h % 360, 1, 1).toColor()];
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(8)), Paint()..shader = LinearGradient(colors: colors).createShader(rect));
    final x = (hue / 360 * size.width).clamp(4.0, size.width - 4);
    final knob = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(x, size.height / 2), width: 8, height: size.height + 4), const Radius.circular(4));
    canvas.drawRRect(knob, Paint()..color = Colors.white);
    canvas.drawRRect(
        knob,
        Paint()
          ..color = Colors.black.withValues(alpha: .4)
          ..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(_HuePainter o) => o.hue != hue;
}

/// A colour setting: the swatch and its hex code, opening the picker.
class ColorRow extends StatelessWidget {
  const ColorRow({super.key, required this.label, required this.color, required this.onChanged});
  final String label;
  final Color color;
  final ValueChanged<Color> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Panel(
        onTap: () async {
          final c = await showColorPicker(context, initial: color, title: label);
          if (c != null) onChanged(c);
        },
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(children: [
          Container(width: 30, height: 30, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(t.zen ? 8 : t.radius), border: Border.all(color: t.line))),
          const SizedBox(width: 12),
          Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
          Text(colorHex(color), style: mono(context, size: 12, color: t.muted, spacing: 0)),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right_sharp, color: t.muted),
        ]),
      ),
    );
  }
}
