import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

import '../../models/doc.dart';

/// Flattens XHTML (EPUB chapters) into reader blocks.
/// [resolveImage] maps an `src` to an extracted file path, or null to skip.
List<Block> htmlToBlocks(String source, {String? Function(String src)? resolveImage, void Function(String id, int block)? onAnchor, int baseIndex = 0}) {
  final doc = html.parse(source);
  final body = doc.body;
  if (body == null) return const [];
  final out = <Block>[];
  final buf = StringBuffer();

  void flush([BlockType type = BlockType.paragraph, int level = 0]) {
    final text = _clean(buf.toString());
    buf.clear();
    if (text.isEmpty) return;
    out.add(Block(type, text: text, level: level));
  }

  void walk(dom.Node node) {
    if (node is dom.Text) {
      buf.write(node.text);
      return;
    }
    if (node is! dom.Element) return;
    final tag = node.localName ?? '';
    final id = node.id;
    if (id.isNotEmpty) onAnchor?.call(id, baseIndex + out.length + (buf.toString().trim().isEmpty ? 0 : 1));

    switch (tag) {
      case 'script':
      case 'style':
      case 'head':
        return;
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        flush();
        buf.write(node.text);
        flush(BlockType.heading, int.parse(tag.substring(1)));
        return;
      case 'blockquote':
        flush();
        final inner = _clean(node.text);
        if (inner.isNotEmpty) out.add(Block(BlockType.quote, text: inner));
        return;
      case 'hr':
        flush();
        out.add(const Block(BlockType.rule));
        return;
      case 'br':
        buf.write('\n');
        return;
      case 'img':
      case 'image':
        final src = node.attributes['src'] ?? node.attributes['xlink:href'] ?? node.attributes['href'];
        if (src != null && resolveImage != null) {
          final path = resolveImage(src);
          if (path != null) {
            flush();
            out.add(Block(BlockType.image, image: path, text: node.attributes['alt'] ?? ''));
          }
        }
        return;
      case 'p':
      case 'div':
      case 'li':
      case 'section':
      case 'article':
      case 'tr':
      case 'dt':
      case 'dd':
      case 'figure':
      case 'figcaption':
      case 'pre':
      case 'table':
      case 'ul':
      case 'ol':
        flush();
        if (tag == 'li') buf.write('• ');
        for (final c in node.nodes) {
          walk(c);
        }
        flush();
        return;
      default:
        for (final c in node.nodes) {
          walk(c);
        }
    }
  }

  for (final n in body.nodes) {
    walk(n);
  }
  flush();
  return out;
}

String _clean(String s) => s
    .replaceAll('­', '')
    .replaceAll(RegExp(r'[ \t\r\f ]+'), ' ')
    .replaceAll(RegExp(r' *\n *'), '\n')
    .replaceAll(RegExp(r'\n{2,}'), '\n')
    .trim();

String stripTags(String s) => _clean(html.parse(s).body?.text ?? s);
