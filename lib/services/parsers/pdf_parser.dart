import 'dart:ui' as ui;

import 'package:pdfrx/pdfrx.dart';

import '../../models/doc.dart';

/// PDF → [ParsedDoc] by text extraction and paragraph reflow.
/// Scanned PDFs yield no blocks; the reader then shows original pages.
Future<ParsedDoc> parsePdf(String path, {void Function(double)? onProgress}) async {
  final doc = await PdfDocument.openFile(path, useProgressiveLoading: false);
  try {
    final blocks = <Block>[];
    final pageStart = <int>[];
    final pages = doc.pages;

    for (var i = 0; i < pages.length; i++) {
      pageStart.add(blocks.length);
      final raw = await pages[i].loadText();
      final text = raw?.fullText ?? '';
      blocks.addAll(_reflow(text, i));
      if (i % 8 == 0) onProgress?.call(i / pages.length);
    }

    // Outline → TOC
    final toc = <TocEntry>[];
    void walk(List<PdfOutlineNode> nodes, int depth) {
      for (final n in nodes) {
        final page = n.dest?.pageNumber;
        if (page != null && page >= 1 && page <= pageStart.length && n.title.trim().isNotEmpty) {
          toc.add(TocEntry(n.title.trim(), pageStart[page - 1], depth: depth));
        }
        walk(n.children, depth + 1);
      }
    }

    try {
      walk(await doc.loadOutline(), 0);
    } catch (_) {}

    // Cover: first page render.
    List<int>? cover;
    try {
      final first = pages.first;
      final w = 600.0;
      final h = w * first.height / first.width;
      final img = await first.render(fullWidth: w, fullHeight: h, backgroundColor: 0xFFFFFFFF);
      if (img != null) {
        final ui.Image image = await img.createImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        cover = bytes?.buffer.asUint8List();
        image.dispose();
        img.dispose();
      }
    } catch (_) {}

    return ParsedDoc(blocks: blocks, toc: toc, coverBytes: cover, pageCount: pages.length);
  } finally {
    await doc.dispose();
  }
}

/// Joins PDF lines into paragraphs: de-hyphenates, and breaks where a
/// short line ends a sentence or a blank line appears.
List<Block> _reflow(String text, int page) {
  final lines = text.replaceAll('\r', '').split('\n').map((l) => l.trimRight()).toList();
  final nonEmpty = lines.where((l) => l.trim().isNotEmpty).map((l) => l.length).toList()..sort();
  if (nonEmpty.isEmpty) return const [];
  final typical = nonEmpty[(nonEmpty.length * .7).floor().clamp(0, nonEmpty.length - 1)];

  final out = <Block>[];
  final buf = StringBuffer();

  void flush() {
    final s = buf.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    buf.clear();
    if (s.isEmpty) return;
    // Lone page numbers / running heads are noise.
    if (RegExp(r'^\d{1,4}$').hasMatch(s)) return;
    final looksHeading = s.length < 70 && !RegExp(r'[.,;:]$').hasMatch(s) && (s == s.toUpperCase() || RegExp(r'^(chapter|part|section)\b', caseSensitive: false).hasMatch(s));
    out.add(Block(looksHeading ? BlockType.heading : BlockType.paragraph, text: s, level: looksHeading ? 2 : 0, page: page));
  }

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line.isEmpty) {
      flush();
      continue;
    }
    if (buf.isNotEmpty) {
      final prev = buf.toString();
      if (prev.endsWith('-') && !prev.endsWith(' -')) {
        buf
          ..clear()
          ..write(prev.substring(0, prev.length - 1));
      } else {
        buf.write(' ');
      }
    }
    buf.write(line);
    final endsSentence = RegExp(r'[.!?:"”’)]$').hasMatch(line);
    final short = line.length < typical * .75;
    final nextStartsUpper = i + 1 < lines.length && RegExp(r'^\s*[A-Z“"(\d•–-]').hasMatch(lines[i + 1]);
    if ((endsSentence && short) || (short && nextStartsUpper && line.length < typical * .5)) flush();
  }
  flush();
  return out;
}
