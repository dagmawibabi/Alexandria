import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/net_image.dart';
import '../core/settings.dart';
import '../core/theme.dart';
import '../core/ui.dart';
import '../models/audiobook.dart';
import '../models/book.dart';
import '../models/podcast.dart';
import '../models/radio.dart';
import 'quote_card.dart';

/// What a share card shows, whatever it is about.
class ShareItem {
  const ShareItem({
    required this.kind,
    required this.title,
    this.subtitle = '',
    this.detail = '',
    this.about = '',
    this.coverPath,
    this.coverUrl,
    this.tallCover = false,
    this.progress,
    this.rating = 0,
    this.note = '',
    this.link,
    this.parent = '',
  });

  /// "Book", "Audiobook", "Chapter", "Podcast", "Episode".
  final String kind;
  final String title;
  final String subtitle;

  /// A short facts line: "12 chapters · 8h 20m".
  final String detail;
  final String about;
  final String? coverPath;
  final String? coverUrl;

  /// Book covers are 2:3; audio artwork is square.
  final bool tallCover;
  final double? progress;
  final int rating;
  final String note;
  final String? link;

  /// The book or show a chapter or episode belongs to.
  final String parent;

  factory ShareItem.book(Book b) => ShareItem(
        kind: 'Book',
        title: b.title,
        subtitle: b.author,
        detail: [b.year, if (b.pageCount > 0) '${b.pageCount} pages'].where((s) => s.isNotEmpty).join(' · '),
        about: b.description,
        coverPath: b.coverPath,
        tallCover: true,
        progress: b.progress,
        rating: b.rating,
      );

  factory ShareItem.audiobook(Audiobook b) => ShareItem(
        kind: 'Audiobook',
        title: b.title,
        subtitle: b.author,
        detail: [if (b.tracks.length > 1) '${b.tracks.length} chapters', if (b.timed) fmtDuration(b.totalMs ~/ 1000)].join(' · '),
        about: b.description,
        coverPath: b.coverPath,
        coverUrl: b.coverUrl,
        progress: b.progress,
        rating: b.mark.rating,
        note: b.mark.notes.firstOrNull?.text ?? '',
      );

  factory ShareItem.chapter(Audiobook b, int i) {
    final t = b.tracks[i.clamp(0, b.tracks.length - 1)];
    return ShareItem(
      kind: 'Chapter ${i + 1} of ${b.tracks.length}',
      title: t.title,
      subtitle: b.author,
      parent: b.title,
      detail: t.ms > 0 ? fmtDuration(t.ms ~/ 1000) : '',
      coverPath: b.coverPath,
      coverUrl: b.coverUrl,
      rating: b.mark.rating,
    );
  }

  factory ShareItem.podcast(Podcast s, UserMark mark) => ShareItem(
        kind: 'Podcast',
        title: s.title,
        subtitle: s.author,
        detail: '${s.episodes.length} episodes',
        about: s.description,
        coverUrl: s.imageUrl,
        rating: mark.rating,
        note: mark.notes.firstOrNull?.text ?? '',
        link: s.link ?? s.feedUrl,
      );

  factory ShareItem.station(Station s, UserMark mark) => ShareItem(
        kind: 'Radio',
        title: s.name,
        subtitle: [s.flag, s.country].where((x) => x.isNotEmpty).join(' '),
        detail: s.tags.take(3).join(' · '),
        coverUrl: s.favicon,
        rating: mark.rating,
        note: mark.notes.firstOrNull?.text ?? '',
        link: s.homepage,
      );

  factory ShareItem.episode(Episode e, {UserMark? mark, double? progress}) => ShareItem(
        kind: 'Episode',
        title: e.title,
        parent: e.podcastTitle,
        detail: [if (e.published != null) '${e.published!.day}.${e.published!.month}.${e.published!.year}', if (e.durationMs > 0) fmtDuration(e.durationMs ~/ 1000)].join(' · '),
        about: e.description,
        coverUrl: e.art,
        progress: progress,
        rating: mark?.rating ?? 0,
        note: mark?.notes.firstOrNull?.text ?? '',
        link: e.link ?? e.audioUrl,
      );
}

void showMediaCard(BuildContext context, ShareItem item) {
  Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => MediaStudio(item: item)));
}

/// Generates a share image for a book, audiobook, chapter, podcast or episode.
class MediaStudio extends StatefulWidget {
  const MediaStudio({super.key, required this.item});
  final ShareItem item;

  @override
  State<MediaStudio> createState() => _MediaStudioState();
}

class _MediaStudioState extends State<MediaStudio> {
  final _key = GlobalKey();
  // Starts on the cover style: these cards are about the artwork.
  int _style = cardStyles.indexWhere((s) => s.cover);
  double _aspect = 4 / 5;
  late bool _brand = Settings.i.quoteBrand;
  bool _about = false;
  bool _progress = false;
  late bool _rating = widget.item.rating > 0;
  bool _note = false;
  bool _sharing = false;

  /// Artwork size, as a share of the card's width.
  late double _artSize = widget.item.tallCover ? .42 : .5;

  Future<void> _share() async {
    setState(() => _sharing = true);
    try {
      final boundary = _key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = await getTemporaryDirectory();
      final f = File(p.join(dir.path, 'alexandria-card-${DateTime.now().millisecondsSinceEpoch}.png'));
      await f.writeAsBytes(bytes!.buffer.asUint8List());
      final i = widget.item;
      await SharePlus.instance.share(ShareParams(
        files: [XFile(f.path, mimeType: 'image/png')],
        text: [i.title, if (i.parent.isNotEmpty) i.parent, if (i.subtitle.isNotEmpty) i.subtitle, if (i.link != null) i.link!].join(' — '),
      ));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final i = widget.item;
    final st = cardWithBackground(cardStyles[_style], Settings.i.cardBg);
    return Scaffold(
      appBar: AppBar(title: AppTitle('${i.kind} card'), actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: ToolButton(Icons.ios_share_sharp, label: _sharing ? '…' : 'Share', active: true, size: 38, onTap: _sharing ? null : _share),
        ),
      ]),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 40), children: [
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * .58),
            child: AspectRatio(
              aspectRatio: _aspect,
              child: RepaintBoundary(
                key: _key,
                child: _MediaCard(item: i, style: st, brand: _brand, about: _about, progress: _progress, rating: _rating, note: _note, artSize: _artSize, accent: Settings.i.signalOn(st.fg)),
              ),
            ),
          ),
        ),
        const SizedBox(height: 22),
        const Label('Style'),
        const SizedBox(height: 8),
        SizedBox(
          height: 56,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (var n = 0; n < cardStyles.length; n++)
              GestureDetector(
                onTap: () {
                  haptic();
                  // A style brings its own background, so this clears any custom one.
                  Settings.i.cardBg = null;
                  setState(() => _style = n);
                },
                child: Container(
                  width: 64,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(color: cardStyles[n].bg, borderRadius: t.br, border: Border.all(color: n == _style ? t.accent : t.line, width: n == _style ? 2 : 1)),
                  alignment: Alignment.center,
                  child: Text(cardStyles[n].name, style: GoogleFonts.getFont(cardStyles[n].font, color: cardStyles[n].fg, fontSize: 11, fontWeight: FontWeight.w600)),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 16),
        CardColorPicker(value: Settings.i.cardBg, onChanged: (c) => setState(() => Settings.i.cardBg = c)),
        SliderRow(label: 'Image size', value: _artSize, min: .2, max: .86, format: (v) => '${(v * 100).round()}%', onChanged: (v) => setState(() => _artSize = v)),
        const SizedBox(height: 8),
        const Label('Format'),
        const SizedBox(height: 8),
        Segmented<double>(values: const [1, 4 / 5, 9 / 16], labels: const ['1:1 Post', '4:5 Feed', '9:16 Story'], value: _aspect, onChanged: (v) => setState(() => _aspect = v)),
        const SizedBox(height: 8),
        ToggleRow(
          label: 'Show Alexandria label',
          value: _brand,
          onChanged: (v) {
            setState(() => _brand = v);
            Settings.i.quoteBrand = v;
          },
        ),
        if (i.rating > 0) ToggleRow(label: 'Show my rating', value: _rating, onChanged: (v) => setState(() => _rating = v)),
        if ((i.progress ?? 0) > 0) ToggleRow(label: 'Show my progress', value: _progress, onChanged: (v) => setState(() => _progress = v)),
        if (i.about.isNotEmpty) ToggleRow(label: 'Include description', value: _about, onChanged: (v) => setState(() => _about = v)),
        if (i.note.isNotEmpty) ToggleRow(label: 'Include my latest note', value: _note, onChanged: (v) => setState(() => _note = v)),
      ]),
    );
  }
}

class _MediaCard extends StatelessWidget {
  const _MediaCard({required this.item, required this.style, required this.brand, required this.about, required this.progress, required this.rating, required this.note, required this.artSize, required this.accent});
  final ShareItem item;
  final CardStyle style;
  final bool brand;
  final bool about;
  final bool progress;
  final bool rating;
  final bool note;
  final double artSize;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final i = item;
    final local = i.coverPath != null && File(i.coverPath!).existsSync() ? i.coverPath : null;
    Widget? art() {
      if (local != null) return monoImage(Image.file(File(local), fit: BoxFit.cover, gaplessPlayback: true));
      if (i.coverUrl != null) return NetImage(i.coverUrl!, fallback: Container(color: style.fg.withValues(alpha: .08)));
      return null;
    }

    final cover = art();
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      final small = GoogleFonts.jetBrainsMono(color: style.fg.withValues(alpha: .65), fontSize: w * .024, letterSpacing: 1.2);
      final font = style.font;
      final artW = w * artSize;
      return Container(
        color: style.bg,
        child: Stack(fit: StackFit.expand, children: [
          if (style.cover && cover != null) ...[
            ImageFiltered(imageFilter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22), child: art()!),
            Container(color: Colors.black.withValues(alpha: .58)),
          ],
          if (style.grid) CustomPaint(painter: CardGrid(style.fg.withValues(alpha: .12))),
          Padding(
            padding: EdgeInsets.all(w * .07),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (brand) ...[
                Row(children: [
                  SizedBox(width: w * .04, height: w * .04, child: CustomPaint(painter: LogoMark(style.fg))),
                  SizedBox(width: w * .02),
                  Text('ALEXANDRIA', style: small),
                ]),
                SizedBox(height: w * .02),
              ],
              // Everything else shrinks together rather than overflowing the card.
              Expanded(
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: SizedBox(
                      width: w * .86,
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Container(
                          width: artW,
                          height: i.tallCover ? artW * 1.5 : artW,
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            color: style.fg.withValues(alpha: .1),
                            borderRadius: BorderRadius.circular(w * .02),
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .35), blurRadius: w * .06, offset: Offset(0, w * .02))],
                          ),
                          child: cover ?? Center(child: Icon(i.kind == 'Book' ? Icons.menu_book_sharp : Icons.graphic_eq_sharp, color: style.fg.withValues(alpha: .5), size: w * .12)),
                        ),
                        SizedBox(height: w * .05),
                        Text(i.kind.toUpperCase(), textAlign: TextAlign.center, style: small.copyWith(color: style.name == 'Signal' ? style.fg : accent)),
                        SizedBox(height: w * .015),
                        Text(i.title, textAlign: TextAlign.center, maxLines: 4, overflow: TextOverflow.ellipsis, style: GoogleFonts.getFont(font, color: style.fg, fontSize: w * .062, height: 1.15, fontWeight: FontWeight.w700)),
                        if (i.parent.isNotEmpty) ...[
                          SizedBox(height: w * .012),
                          Text(i.parent, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: GoogleFonts.getFont(font, color: style.fg.withValues(alpha: .85), fontSize: w * .036, fontWeight: FontWeight.w500)),
                        ],
                        if (i.subtitle.isNotEmpty) ...[
                          SizedBox(height: w * .012),
                          Text(i.subtitle, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: GoogleFonts.getFont(font, color: style.fg.withValues(alpha: .75), fontSize: w * .034)),
                        ],
                        if (i.detail.isNotEmpty) ...[
                          SizedBox(height: w * .018),
                          Text(i.detail.toUpperCase(), textAlign: TextAlign.center, style: small),
                        ],
                        if (rating && i.rating > 0) ...[
                          SizedBox(height: w * .025),
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            for (var n = 1; n <= 5; n++) Icon(n <= i.rating ? Icons.star_sharp : Icons.star_border_sharp, size: w * .045, color: style.name == 'Signal' ? style.fg : accent),
                          ]),
                        ],
                        if (progress && (i.progress ?? 0) > 0) ...[
                          SizedBox(height: w * .03),
                          SizedBox(
                            width: w * .5,
                            child: Stack(children: [
                              Container(height: w * .008, color: style.fg.withValues(alpha: .2)),
                              FractionallySizedBox(widthFactor: i.progress!.clamp(.01, 1), child: Container(height: w * .008, color: style.name == 'Signal' ? style.fg : accent)),
                            ]),
                          ),
                          SizedBox(height: w * .012),
                          Text('${(i.progress! * 100).round()}%', style: small),
                        ],
                        if (about && i.about.isNotEmpty) ...[
                          SizedBox(height: w * .03),
                          Text(i.about, textAlign: TextAlign.center, maxLines: 6, overflow: TextOverflow.ellipsis, style: GoogleFonts.getFont(font, color: style.fg.withValues(alpha: .8), fontSize: w * .03, height: 1.35)),
                        ],
                        if (note && i.note.isNotEmpty) ...[
                          SizedBox(height: w * .03),
                          Text('“${i.note}”', textAlign: TextAlign.center, maxLines: 5, overflow: TextOverflow.ellipsis, style: GoogleFonts.getFont(font, color: style.fg, fontSize: w * .034, height: 1.35, fontStyle: FontStyle.italic)),
                        ],
                      ]),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ]),
      );
    });
  }
}
