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

  static Directory get _dir => Directory(p.join(Storage.cache.path, 'img'));

  static File fileFor(String url) => File(p.join(_dir.path, sha1.convert(utf8.encode(url)).toString()));

  /// The cached file for [url], if it has been fetched before.
  static File? cached(String url) {
    final f = fileFor(url);
    return f.existsSync() && f.lengthSync() > 0 ? f : null;
  }

  static Future<File?> get(String url) {
    final hit = cached(url);
    if (hit != null) return Future.value(hit);
    return _inflight[url] ??= () async {
      try {
        final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
        if (r.statusCode != 200 || r.bodyBytes.isEmpty) return null;
        await _dir.create(recursive: true);
        final f = fileFor(url);
        final tmp = File('${f.path}.tmp');
        await tmp.writeAsBytes(r.bodyBytes, flush: true);
        await tmp.rename(f.path);
        return f;
      } catch (_) {
        return null;
      } finally {
        _inflight.remove(url);
      }
    }();
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
    if (_file != null) return;
    final url = widget.url;
    NetImageCache.get(url).then((f) {
      if (!mounted || widget.url != url) return;
      if (f != null) setState(() => _file = f);
    });
  }

  @override
  Widget build(BuildContext context) {
    final fallback = widget.fallback ?? SizedBox(width: widget.width, height: widget.height);
    final f = _file;
    if (f == null) return fallback;
    return monoImage(Image.file(f, fit: widget.fit, width: widget.width, height: widget.height, gaplessPlayback: true, errorBuilder: (_, _, _) => fallback));
  }
}
