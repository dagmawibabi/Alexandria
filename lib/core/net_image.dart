import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import '../services/storage.dart';
import 'ui.dart';

/// Network images kept on disk, so covers and thumbnails load once and then
/// show instantly (and offline).
class NetImageCache {
  NetImageCache._();

  static final Map<String, Future<File?>> _inflight = {};

  /// URLs known to be on disk. Checking the disk is synchronous, so each URL
  /// is checked once a session instead of on every build of every thumbnail.
  static final Map<String, File> _known = {};

  /// One client for every image: covers mostly come from a few hosts, and a
  /// kept-alive connection skips a new TLS handshake for each one.
  static final _client = http.Client();

  static Directory get _dir => Directory(p.join(Storage.cache.path, 'img'));

  static File fileFor(String url) => File(p.join(_dir.path, sha1.convert(utf8.encode(url)).toString()));

  /// The cached file for [url], if it has been fetched before.
  static File? cached(String url) {
    final hit = _known[url];
    if (hit != null) return hit;
    final f = fileFor(url);
    if (f.existsSync() && f.lengthSync() > 0) return _known[url] = f;
    return null;
  }

  static Future<File?> get(String url) {
    final hit = cached(url);
    if (hit != null) return Future.value(hit);
    return _inflight[url] ??= () async {
      try {
        final r = await _client.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
        if (r.statusCode != 200 || r.bodyBytes.isEmpty) return null;
        await _dir.create(recursive: true);
        final f = fileFor(url);
        final tmp = File('${f.path}.tmp');
        await tmp.writeAsBytes(r.bodyBytes, flush: true);
        await tmp.rename(f.path);
        return _known[url] = f;
      } catch (_) {
        return null;
      } finally {
        _inflight.remove(url);
      }
    }();
  }
}

/// Whether a local file exists, remembered once it does. Covers are checked
/// on every build of every grid tile; this keeps that off the disk.
bool fileExists(String? path) {
  if (path == null || path.isEmpty) return false;
  if (_existing.contains(path)) return true;
  if (!File(path).existsSync()) return false;
  _existing.add(path);
  return true;
}

final _existing = <String>{};

/// An image file decoded at the size it's shown, not its full size. Podcast
/// art is often 3000 px square (36 MB decoded) for a 60 px thumbnail; this is
/// what keeps lists light and scrolling smooth.
class SizedFileImage extends StatelessWidget {
  const SizedFileImage(this.file, {super.key, this.fit = BoxFit.cover, this.width, this.height, this.errorBuilder, this.fadeIn = false});
  final File file;
  final BoxFit fit;
  final double? width;
  final double? height;
  final ImageErrorWidgetBuilder? errorBuilder;

  /// Fades in when it wasn't ready at once (just downloaded).
  final bool fadeIn;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2;
      final w = width ?? (box.hasBoundedWidth ? box.maxWidth : null);
      final h = height ?? (box.hasBoundedHeight ? box.maxHeight : null);
      // Decode to cover the larger side so BoxFit.cover never upscales; the
      // other side follows the image's own aspect ratio.
      final side = [w, h].whereType<double>().fold<double>(0, (a, b) => b > a ? b : a);
      final px = side > 0 && side.isFinite ? (side * dpr).ceil() : null;
      final ImageProvider provider = px == null ? FileImage(file) : ResizeImage(FileImage(file), width: px, height: px, policy: ResizeImagePolicy.fit, allowUpscaling: false);
      return Image(
        image: provider,
        fit: fit,
        width: width,
        height: height,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        errorBuilder: errorBuilder,
        frameBuilder: !fadeIn
            ? null
            : (context, child, frame, sync) => sync ? child : AnimatedOpacity(opacity: frame == null ? 0 : 1, duration: const Duration(milliseconds: 180), curve: Curves.easeOut, child: child),
      );
    });
  }
}

class NetImage extends StatefulWidget {
  const NetImage(this.url, {super.key, this.fit = BoxFit.cover, this.width, this.height, this.fallback});

  final String url;
  final BoxFit fit;
  final double? width;
  final double? height;

  /// Shown while loading and when the image can't be fetched.
  final Widget? fallback;

  @override
  State<NetImage> createState() => _NetImageState();
}

class _NetImageState extends State<NetImage> {
  File? _file;

  /// Fetched while on screen (not already cached): fade it in rather than pop.
  bool _arrived = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(NetImage old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) _load();
  }

  void _load() {
    _file = NetImageCache.cached(widget.url);
    _arrived = false;
    if (_file != null) return;
    final url = widget.url;
    NetImageCache.get(url).then((f) {
      if (!mounted || widget.url != url) return;
      if (f != null) {
        setState(() {
          _file = f;
          _arrived = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final fallback = widget.fallback ?? SizedBox(width: widget.width, height: widget.height);
    final f = _file;
    if (f == null) return fallback;
    final img = SizedFileImage(f, fit: widget.fit, width: widget.width, height: widget.height, fadeIn: _arrived, errorBuilder: (_, _, _) => fallback);
    // The placeholder stays underneath while the image fades in over it.
    return monoImage(_arrived ? Stack(fit: StackFit.passthrough, children: [Positioned.fill(child: fallback), img]) : img);
  }
}
