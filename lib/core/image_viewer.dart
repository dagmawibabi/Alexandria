import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import 'net_image.dart';
import 'ui.dart';

/// Opens an image full screen: pinch or double-tap to zoom, drag to pan, and
/// share or save it to the device. Give a local [path] or a web [url].
Future<void> openImageViewer(BuildContext context, {String? url, String? path, String title = 'Image'}) {
  if (url == null && path == null) return Future.value();
  return Navigator.of(context).push(PageRouteBuilder(
    opaque: false,
    barrierColor: Colors.black,
    transitionDuration: const Duration(milliseconds: 200),
    reverseTransitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (_, _, _) => ImageViewer(url: url, path: path, title: title),
    transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: CurvedAnimation(parent: a, curve: Curves.easeOut), child: child),
  ));
}

/// Makes [child] open [url] or [path] in the full-screen viewer when tapped.
/// Without an image to show, [child] is returned as it is.
class ViewableImage extends StatelessWidget {
  const ViewableImage({super.key, this.url, this.path, required this.title, required this.child});
  final String? url;
  final String? path;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final local = path != null && path!.isNotEmpty ? path : null;
    final web = url != null && url!.isNotEmpty ? url : null;
    if (local == null && web == null) return child;
    return Semantics(
      button: true,
      hint: 'View the image full screen',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          haptic();
          openImageViewer(context, url: web, path: local, title: title);
        },
        child: child,
      ),
    );
  }
}

class ImageViewer extends StatefulWidget {
  const ImageViewer({super.key, this.url, this.path, required this.title});
  final String? url;
  final String? path;
  final String title;

  @override
  State<ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<ImageViewer> with SingleTickerProviderStateMixin {
  final _zoom = TransformationController();
  late final _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
  Animation<Matrix4>? _to;
  Offset _tapAt = Offset.zero;

  File? _file;
  bool _failed = false;
  bool _chrome = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _anim.addListener(() {
      if (_to != null) _zoom.value = _to!.value;
    });
    _load();
  }

  Future<void> _load() async {
    final path = widget.path;
    if (path != null) {
      final f = File(path);
      if (await f.exists()) return _show(f);
    }
    final url = widget.url;
    if (url == null) return setState(() => _failed = true);
    // Usually already on disk, from the thumbnail that was tapped.
    final f = await NetImageCache.get(url);
    if (!mounted) return;
    f == null ? setState(() => _failed = true) : _show(f);
  }

  void _show(File f) {
    if (mounted) setState(() => _file = f);
  }

  @override
  void dispose() {
    _anim.dispose();
    _zoom.dispose();
    super.dispose();
  }

  /// Double tap: zoom in on the spot tapped, or back out.
  void _toggleZoom() {
    final zoomed = _zoom.value.getMaxScaleOnAxis() > 1.01;
    const scale = 2.6;
    final p = _tapAt;
    final end = zoomed
        ? Matrix4.identity()
        : (Matrix4.identity()
          ..translateByDouble(-p.dx * (scale - 1), -p.dy * (scale - 1), 0, 1)
          ..scaleByDouble(scale, scale, 1, 1));
    _to = Matrix4Tween(begin: _zoom.value, end: end).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));
    _anim.forward(from: 0);
  }

  /// The file's real type, from its first bytes: cached images have no extension.
  static (String ext, String mime) _kind(List<int> b) {
    if (b.length > 3 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return ('png', 'image/png');
    if (b.length > 2 && b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) return ('gif', 'image/gif');
    if (b.length > 11 && String.fromCharCodes(b.sublist(8, 12)) == 'WEBP') return ('webp', 'image/webp');
    return ('jpg', 'image/jpeg');
  }

  String get _name {
    final clean = widget.title.replaceAll(RegExp(r'[\\/:*?"<>|\n\r]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    return clean.isEmpty ? 'image' : (clean.length > 80 ? clean.substring(0, 80).trim() : clean);
  }

  Future<void> _save() async {
    final f = _file;
    if (f == null || _busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await f.readAsBytes();
      final (ext, mime) = _kind(bytes);
      final saved = await FilePicker.saveFile(fileName: '$_name.$ext', bytes: bytes, mimeType: mime, dialogTitle: 'Save image');
      if (mounted && saved != null) toast(context, 'Image saved');
    } catch (_) {
      if (mounted) toast(context, 'Couldn’t save the image');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    final f = _file;
    if (f == null) return;
    final head = await f.openRead(0, 12).fold<List<int>>([], (a, b) => a..addAll(b));
    final (ext, mime) = _kind(head);
    // Shared as a properly named copy, so the receiving app knows what it is.
    final copy = await f.copy('${Directory.systemTemp.path}${Platform.pathSeparator}$_name.$ext');
    await SharePlus.instance.share(ShareParams(files: [XFile(copy.path, mimeType: mime)], subject: widget.title));
  }

  @override
  Widget build(BuildContext context) {
    final f = _file;
    const ink = Colors.white;
    Widget body;
    if (f != null) {
      body = GestureDetector(
        onTap: () => setState(() => _chrome = !_chrome),
        onDoubleTapDown: (d) => _tapAt = d.localPosition,
        onDoubleTap: _toggleZoom,
        child: InteractiveViewer(
          transformationController: _zoom,
          minScale: 1,
          maxScale: 8,
          child: SizedBox.expand(
            // Full resolution here: this is where the detail is wanted.
            child: Image.file(f, fit: BoxFit.contain, gaplessPlayback: true, errorBuilder: (_, _, _) => const Center(child: Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48))),
          ),
        ),
      );
    } else if (_failed) {
      body = const Center(child: Text('Couldn’t load this image.', style: TextStyle(color: Colors.white70)));
    } else {
      body = const Center(child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white70));
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(fit: StackFit.expand, children: [
        body,
        AnimatedOpacity(
          opacity: _chrome ? 1 : 0,
          duration: const Duration(milliseconds: 160),
          child: IgnorePointer(
            ignoring: !_chrome,
            child: Align(
              alignment: Alignment.topCenter,
              child: DecoratedBox(
                decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black.withValues(alpha: .7), Colors.transparent])),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 4, 20),
                    child: Row(children: [
                      IconButton(tooltip: 'Close', onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.close_sharp, color: ink)),
                      Expanded(child: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: ink, fontWeight: FontWeight.w600))),
                      IconButton(tooltip: 'Share', onPressed: f == null ? null : _share, icon: Icon(Icons.ios_share_sharp, color: f == null ? Colors.white38 : ink)),
                      IconButton(
                        tooltip: 'Save to device',
                        onPressed: f == null || _busy ? null : _save,
                        icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 1.5, color: ink)) : Icon(Icons.download_sharp, color: f == null ? Colors.white38 : ink),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
