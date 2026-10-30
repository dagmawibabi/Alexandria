import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../../models/doc.dart';
import 'epub_parser.dart' show headingsToc;

/// DOCX → [ParsedDoc]. Paragraph styles become headings/quotes, inline
/// pictures are extracted, core properties give title and author.
Future<ParsedDoc> parseDocx(List<int> bytes, Directory imageDir) async {
  final zip = ZipDecoder().decodeBytes(bytes);
  final files = <String, ArchiveFile>{for (final f in zip.files) if (f.isFile) f.name: f};
  String? text(String n) => files[n] == null ? null : utf8.decode(files[n]!.content, allowMalformed: true);

  final document = XmlDocument.parse(text('word/document.xml') ?? '<x/>');

  // styleId → human style name ("heading 1", "Title", "Quote")
  final styleNames = <String, String>{};
  final styles = text('word/styles.xml');
  if (styles != null) {
    for (final s in XmlDocument.parse(styles).findAllElements('style', namespace: '*')) {
      final id = s.getAttribute('w:styleId') ?? s.getAttribute('styleId', namespace: '*');
      final name = s.findElements('name', namespace: '*').firstOrNull?.getAttribute('w:val');
      if (id != null && name != null) styleNames[id] = name.toLowerCase();
    }
  }

  // relationship id → media path
  final rels = <String, String>{};
  final relXml = text('word/_rels/document.xml.rels');
  if (relXml != null) {
    for (final r in XmlDocument.parse(relXml).findAllElements('Relationship', namespace: '*')) {
      final id = r.getAttribute('Id');
      final target = r.getAttribute('Target');
      if (id != null && target != null) rels[id] = p.posix.normalize(target.startsWith('/') ? target.substring(1) : 'word/$target');
    }
  }

  await imageDir.create(recursive: true);
  var imageCount = 0;
  final blocks = <Block>[];

  for (final para in document.findAllElements('p', namespace: '*')) {
    if (para.name.prefix != 'w') continue;
    final pPr = para.findElements('pPr', namespace: '*').firstOrNull;
    final styleId = pPr?.findElements('pStyle', namespace: '*').firstOrNull?.getAttribute('w:val') ?? '';
    final styleName = styleNames[styleId] ?? styleId.toLowerCase();
    final outline = pPr?.findElements('outlineLvl', namespace: '*').firstOrNull?.getAttribute('w:val');
    final isList = pPr?.findElements('numPr', namespace: '*').isNotEmpty ?? false;

    final buf = StringBuffer();
    for (final node in para.descendants.whereType<XmlElement>()) {
      switch (node.localName) {
        case 't':
          buf.write(node.innerText);
        case 'tab':
          buf.write('\t');
        case 'br':
        case 'cr':
          buf.write('\n');
        case 'blip':
          final rid = node.getAttribute('r:embed');
          final media = rels[rid];
          final f = media == null ? null : files[media];
          if (f != null) {
            final out = File(p.join(imageDir.path, 'd${imageCount++}${p.extension(media!)}'));
            await out.writeAsBytes(f.content);
            if (buf.toString().trim().isNotEmpty) {
              blocks.add(Block(BlockType.paragraph, text: buf.toString().trim()));
              buf.clear();
            }
            blocks.add(Block(BlockType.image, image: out.path));
          }
      }
    }
    final s = buf.toString().replaceAll(RegExp(r'[  ]+'), ' ').trim();
    if (s.isEmpty) continue;

    final heading = RegExp(r'heading\s*(\d)').firstMatch(styleName);
    if (styleName == 'title') {
      blocks.add(Block(BlockType.heading, text: s, level: 1));
    } else if (styleName == 'subtitle') {
      blocks.add(Block(BlockType.heading, text: s, level: 3));
    } else if (heading != null) {
      blocks.add(Block(BlockType.heading, text: s, level: int.parse(heading.group(1)!).clamp(1, 6)));
    } else if (outline != null) {
      blocks.add(Block(BlockType.heading, text: s, level: (int.tryParse(outline) ?? 0) + 1));
    } else if (styleName.contains('quote')) {
      blocks.add(Block(BlockType.quote, text: s));
    } else {
      blocks.add(Block(BlockType.paragraph, text: isList ? '• $s' : s));
    }
  }

  String? core(String name) {
    final c = text('docProps/core.xml');
    if (c == null) return null;
    final v = XmlDocument.parse(c).findAllElements(name, namespace: '*').firstOrNull?.innerText.trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  return ParsedDoc(
    blocks: blocks,
    toc: headingsToc(blocks),
    title: core('title'),
    author: core('creator'),
    description: core('description'),
    year: RegExp(r'\d{4}').firstMatch(core('created') ?? '')?.group(0),
  );
}
