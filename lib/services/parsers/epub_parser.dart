import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../../models/doc.dart';
import 'html_blocks.dart';

/// EPUB 2/3 → [ParsedDoc]. Reads the OPF, spine, NAV/NCX table of contents,
/// metadata and cover; extracts images into [imageDir].
Future<ParsedDoc> parseEpub(List<int> bytes, Directory imageDir) async {
  final zip = ZipDecoder().decodeBytes(bytes);
  final files = <String, ArchiveFile>{for (final f in zip.files) if (f.isFile) f.name: f};

  String? readText(String name) {
    final f = files[name] ?? files[Uri.decodeFull(name)];
    if (f == null) return null;
    return utf8.decode(f.content, allowMalformed: true);
  }

  final container = XmlDocument.parse(readText('META-INF/container.xml') ?? '<x/>');
  final opfPath = container.findAllElements('rootfile', namespace: '*').firstOrNull?.getAttribute('full-path') ?? _guessOpf(files.keys);
  final opfDir = p.posix.dirname(opfPath) == '.' ? '' : p.posix.dirname(opfPath);
  final opf = XmlDocument.parse(readText(opfPath) ?? '<package/>');

  String resolve(String base, String href) {
    final clean = Uri.decodeFull(href.split('#').first);
    return p.posix.normalize(base.isEmpty ? clean : p.posix.join(base, clean));
  }

  String? meta(String name) {
    final e = opf.findAllElements(name, namespace: '*').firstOrNull;
    final v = e?.innerText.trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  // ---- manifest ----
  final manifest = <String, ({String href, String type, String props})>{};
  for (final item in opf.findAllElements('item', namespace: '*')) {
    final id = item.getAttribute('id');
    final href = item.getAttribute('href');
    if (id == null || href == null) continue;
    manifest[id] = (href: resolve(opfDir, href), type: item.getAttribute('media-type') ?? '', props: item.getAttribute('properties') ?? '');
  }

  // ---- cover ----
  List<int>? cover;
  String? coverHref = manifest.values.where((m) => m.props.contains('cover-image')).firstOrNull?.href;
  if (coverHref == null) {
    final coverId = opf.findAllElements('meta', namespace: '*').where((m) => m.getAttribute('name') == 'cover').firstOrNull?.getAttribute('content');
    coverHref = manifest[coverId]?.href;
  }
  coverHref ??= manifest.entries.where((e) => e.value.type.startsWith('image/') && e.key.toLowerCase().contains('cover')).firstOrNull?.value.href;
  if (coverHref != null) cover = files[coverHref]?.content;

  // ---- spine → blocks ----
  final spine = opf.findAllElements('itemref', namespace: '*').map((e) => e.getAttribute('idref')).whereType<String>().toList();
  final blocks = <Block>[];
  final chapterStart = <String, int>{};
  final anchors = <String, int>{};
  final extracted = <String, String>{};
  await imageDir.create(recursive: true);

  for (final idref in spine) {
    final item = manifest[idref];
    if (item == null) continue;
    final src = readText(item.href);
    if (src == null) continue;
    final dir = p.posix.dirname(item.href) == '.' ? '' : p.posix.dirname(item.href);
    chapterStart[item.href] = blocks.length;

    String? resolveImage(String s) {
      final full = resolve(dir, s);
      if (extracted.containsKey(full)) return extracted[full];
      final f = files[full];
      if (f == null) return null;
      final out = File(p.join(imageDir.path, '${extracted.length}${p.extension(full)}'));
      out.writeAsBytesSync(f.content);
      return extracted[full] = out.path;
    }

    blocks.addAll(htmlToBlocks(
      src,
      resolveImage: resolveImage,
      baseIndex: blocks.length,
      onAnchor: (id, b) => anchors['${item.href}#$id'] = b,
    ));
  }

  // ---- table of contents ----
  var toc = <TocEntry>[];
  int? target(String base, String href) {
    final file = resolve(base, href);
    final frag = href.contains('#') ? href.split('#').last : null;
    if (frag != null && anchors.containsKey('$file#$frag')) return anchors['$file#$frag'];
    return chapterStart[file];
  }

  final navItem = manifest.values.where((m) => m.props.split(' ').contains('nav')).firstOrNull;
  if (navItem != null) {
    final navDir = p.posix.dirname(navItem.href) == '.' ? '' : p.posix.dirname(navItem.href);
    final navDoc = XmlDocument.parse(_xmlSafe(readText(navItem.href) ?? '<x/>'));
    final nav = navDoc.findAllElements('nav', namespace: '*').where((n) => (n.getAttribute('epub:type') ?? n.getAttribute('type', namespace: '*') ?? '').contains('toc')).firstOrNull ??
        navDoc.findAllElements('nav', namespace: '*').firstOrNull;
    if (nav != null) {
      void walk(XmlElement ol, int depth) {
        for (final li in ol.childElements.where((e) => e.localName == 'li')) {
          final a = li.childElements.where((e) => e.localName == 'a' || e.localName == 'span').firstOrNull;
          final href = a?.getAttribute('href');
          final title = a?.innerText.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
          final b = href == null ? null : target(navDir, href);
          if (b != null && title.isNotEmpty) toc.add(TocEntry(title, b, depth: depth));
          for (final sub in li.childElements.where((e) => e.localName == 'ol')) {
            walk(sub, depth + 1);
          }
        }
      }

      for (final ol in nav.childElements.where((e) => e.localName == 'ol')) {
        walk(ol, 0);
      }
    }
  }

  if (toc.isEmpty) {
    final ncxId = opf.findAllElements('spine', namespace: '*').firstOrNull?.getAttribute('toc');
    final ncxHref = manifest[ncxId]?.href ?? manifest.values.where((m) => m.type.contains('dtbncx')).firstOrNull?.href;
    if (ncxHref != null) {
      final ncxDir = p.posix.dirname(ncxHref) == '.' ? '' : p.posix.dirname(ncxHref);
      final ncx = XmlDocument.parse(readText(ncxHref) ?? '<x/>');
      void walk(XmlElement parent, int depth) {
        for (final np in parent.childElements.where((e) => e.localName == 'navPoint')) {
          final title = np.findAllElements('text', namespace: '*').firstOrNull?.innerText.trim() ?? '';
          final src = np.findAllElements('content', namespace: '*').firstOrNull?.getAttribute('src');
          final b = src == null ? null : target(ncxDir, src);
          if (b != null && title.isNotEmpty) toc.add(TocEntry(title, b, depth: depth));
          walk(np, depth + 1);
        }
      }

      final map = ncx.findAllElements('navMap', namespace: '*').firstOrNull;
      if (map != null) walk(map, 0);
    }
  }

  if (toc.isEmpty) toc = headingsToc(blocks);
  toc.sort((a, b) => a.block.compareTo(b.block));

  final isbn = opf
      .findAllElements('identifier', namespace: '*')
      .map((e) => e.innerText.replaceAll(RegExp(r'[^0-9X]'), ''))
      .where((s) => s.length == 10 || s.length == 13)
      .firstOrNull;

  return ParsedDoc(
    blocks: blocks,
    toc: toc,
    title: meta('title'),
    author: opf.findAllElements('creator', namespace: '*').map((e) => e.innerText.trim()).where((s) => s.isNotEmpty).join(', '),
    description: meta('description') == null ? null : stripTags(meta('description')!),
    publisher: meta('publisher'),
    language: meta('language'),
    year: RegExp(r'\d{4}').firstMatch(meta('date') ?? '')?.group(0),
    isbn: isbn,
    coverBytes: cover,
  );
}

String _guessOpf(Iterable<String> names) => names.firstWhere((n) => n.endsWith('.opf'), orElse: () => 'content.opf');

/// NAV documents are XHTML but sometimes contain HTML entities XML rejects.
String _xmlSafe(String s) => s.replaceAll('&nbsp;', '&#160;');

/// Fallback TOC from headings.
List<TocEntry> headingsToc(List<Block> blocks) => [
      for (var i = 0; i < blocks.length; i++)
        if (blocks[i].type == BlockType.heading && blocks[i].level <= 2 && blocks[i].text.length < 120)
          TocEntry(blocks[i].text, i, depth: blocks[i].level - 1),
    ];
