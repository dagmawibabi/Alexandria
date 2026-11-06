import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A reader surface: page colour + ink colour.
class Surface {
  const Surface(this.id, this.name, this.bg, this.fg, {this.dark = false});

  final String id;
  final String name;
  final Color bg;
  final Color fg;
  final bool dark;
}

const surfaces = <Surface>[
  Surface('paper', 'Paper', Color(0xFFF2EFE8), Color(0xFF1C1B19)),
  Surface('white', 'White', Color(0xFFFFFFFF), Color(0xFF111111)),
  Surface('sepia', 'Sepia', Color(0xFFF1E4C9), Color(0xFF47392A)),
  Surface('fog', 'Fog', Color(0xFFE3E5E2), Color(0xFF222624)),
  Surface('sage', 'Sage', Color(0xFFDCE3D5), Color(0xFF26301F)),
  Surface('concrete', 'Concrete', Color(0xFFBDBCB8), Color(0xFF151515)),
  Surface('graphite', 'Graphite', Color(0xFF2A2B2D), Color(0xFFD9D8D3), dark: true),
  Surface('slate', 'Slate', Color(0xFF1B2128), Color(0xFFC9D1DA), dark: true),
  Surface('amber', 'Amber CRT', Color(0xFF120F08), Color(0xFFE7B867), dark: true),
  Surface('phosphor', 'Phosphor', Color(0xFF07110A), Color(0xFF86E39A), dark: true),
  Surface('oled', 'OLED', Color(0xFF000000), Color(0xFFB8B8B8), dark: true),
];

const accents = <Color>[
  Color(0xFFFF5A1F), // signal orange
  Color(0xFFFFC300), // safety yellow
  Color(0xFF2D6BFF), // klein-ish blue
  Color(0xFF00A86B), // instrument green
  Color(0xFFE5243B), // stop red
  Color(0xFF9B9B93), // aluminium
  Color(0xFF7B61FF), // violet
  Color(0xFF00B3C7), // teal
  Color(0xFFFF4F9A), // magenta
  Color(0xFF8A6A3B), // bronze
  Color(0xFFFFFFFF), // white
];

const accentNames = <int, String>{
  0xFFFF5A1F: 'Signal orange',
  0xFFFFC300: 'Safety yellow',
  0xFF2D6BFF: 'Klein blue',
  0xFF00A86B: 'Instrument green',
  0xFFE5243B: 'Stop red',
  0xFF9B9B93: 'Aluminium',
  0xFF7B61FF: 'Violet',
  0xFF00B3C7: 'Teal',
  0xFFFF4F9A: 'Magenta',
  0xFF8A6A3B: 'Bronze',
  0xFFFFFFFF: 'White',
};

const highlightColors = <Color>[
  Color(0xFFFFD54A),
  Color(0xFFFF8A65),
  Color(0xFF7FD1AE),
  Color(0xFF7FB2FF),
  Color(0xFFD59BFF),
  Color(0xFFFF8FC0),
  Color(0xFF5FD3E0),
];

const readerFonts = <String>[
  'Literata',
  'Source Serif 4',
  'EB Garamond',
  'Crimson Pro',
  'Newsreader',
  'IBM Plex Serif',
  'Inter',
  'IBM Plex Sans',
  'Space Grotesk',
  'Atkinson Hyperlegible',
  'JetBrains Mono',
  'IBM Plex Mono',
];

const uiFonts = <String>['Space Grotesk', 'Inter', 'IBM Plex Sans', 'Archivo', 'JetBrains Mono'];

enum EdgeSide { left, right, both, off }

class Settings extends ChangeNotifier {
  Settings._();
  static final Settings i = Settings._();

  late SharedPreferences _prefs;
  final Map<String, dynamic> _v = {};

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs.getString('settings');
    if (raw != null) _v.addAll(jsonDecode(raw));
  }

  T _get<T>(String k, T d) {
    final v = _v[k];
    if (v == null) return d;
    if (T == double && v is int) return v.toDouble() as T;
    return v is T ? v : d;
  }

  void set(String k, Object? v) {
    _v[k] = v;
    _prefs.setString('settings', jsonEncode(_v));
    notifyListeners();
  }

  /// Every setting, for backups.
  Map<String, dynamic> exportJson() => Map<String, dynamic>.from(_v);

  /// Applies settings from a backup over the current ones.
  void importJson(Map<String, dynamic> j) {
    _v.addAll(j);
    _prefs.setString('settings', jsonEncode(_v));
    notifyListeners();
  }

  void reset(Iterable<String> keys) {
    for (final k in keys) {
      _v.remove(k);
    }
    _prefs.setString('settings', jsonEncode(_v));
    notifyListeners();
  }

  // ---------- interface ----------
  /// Zen: a calm, modern, minimal look for every screen instead of the industrial one.
  bool get zen => _get('zen', false);
  set zen(bool v) => set('zen', v);

  /// Monochrome: no signal colour; accents use the ink colour and covers go grey.
  bool get mono => _get('mono', false);
  set mono(bool v) => set('mono', v);

  /// The accent to draw on a surface whose ink is [fg] (the reader page, for example).
  /// Anything that would vanish against that surface, like white on a light page,
  /// follows the ink instead.
  Color signalOn(Color fg) {
    if (mono) return fg;
    final l = accent.computeLuminance();
    final surfaceIsDark = fg.computeLuminance() > .5;
    return (surfaceIsDark && l < .02) || (!surfaceIsDark && l > .8) ? fg : accent;
  }

  ThemeMode get themeMode => ThemeMode.values[_get('themeMode', 0)];
  set themeMode(ThemeMode m) => set('themeMode', m.index);

  Color get accent => Color(_get('accent', accents.first.toARGB32()));
  set accent(Color c) => set('accent', c.toARGB32());

  double get radius => _get('radius', 2.0);
  set radius(double v) => set('radius', v);

  String get uiFont => _get('uiFont', 'Space Grotesk');
  set uiFont(String v) => set('uiFont', v);

  bool get dotGrid => _get('dotGrid', true);
  set dotGrid(bool v) => set('dotGrid', v);

  bool get haptics => _get('haptics', true);
  set haptics(bool v) => set('haptics', v);

  bool get libraryGrid => _get('libraryGrid', true);
  set libraryGrid(bool v) => set('libraryGrid', v);

  int get gridColumns => _get('gridColumns', 3);
  set gridColumns(int v) => set('gridColumns', v);

  String get librarySort => _get('librarySort', 'recent');
  set librarySort(String v) => set('librarySort', v);

  bool get showProgressOnCovers => _get('showProgressOnCovers', true);
  set showProgressOnCovers(bool v) => set('showProgressOnCovers', v);

  bool get autoFetchMetadata => _get('autoFetchMetadata', true);
  set autoFetchMetadata(bool v) => set('autoFetchMetadata', v);

  int get dailyGoalMinutes => _get('dailyGoalMinutes', 30);
  set dailyGoalMinutes(int v) => set('dailyGoalMinutes', v);

  int get yearlyGoalBooks => _get('yearlyGoalBooks', 24);
  set yearlyGoalBooks(int v) => set('yearlyGoalBooks', v);

  int get yearlyGoalAudiobooks => _get('yearlyGoalAudiobooks', 12);
  set yearlyGoalAudiobooks(int v) => set('yearlyGoalAudiobooks', v);

  int get weeklyGoalEpisodes => _get('weeklyGoalEpisodes', 5);
  set weeklyGoalEpisodes(int v) => set('weeklyGoalEpisodes', v);

  /// Look of one home-screen widget, as saved by the widget customiser.
  Map<String, dynamic> widgetStyle(String kind) => Map<String, dynamic>.from(_get<Map>('widget.$kind', const {}));
  void setWidgetStyle(String kind, Map<String, dynamic> v) => set('widget.$kind', v);

  /// Downloads to resume next launch (see Downloads).
  List<String> get pendingDownloads => _get<List>('pendingDownloads', const []).cast<String>();
  set pendingDownloads(List<String> v) => set('pendingDownloads', v);

  /// Grid or list on the folder pages.
  bool get folderGrid => _get('folderGrid', true);
  set folderGrid(bool v) => set('folderGrid', v);

  /// The country the Radio tab is showing ('' for all), and its name.
  String get radioCountry => _get('radioCountry', '');
  set radioCountry(String v) => set('radioCountry', v);
  String get radioCountryName => _get('radioCountryName', '');
  set radioCountryName(String v) => set('radioCountryName', v);

  // ---------- podcasts ----------
  /// Check for new episodes in the background and send a notification.
  bool get podcastAlerts => _get('podcastAlerts', true);
  set podcastAlerts(bool v) => set('podcastAlerts', v);

  int get podcastCheckHours => _get('podcastCheckHours', 6);
  set podcastCheckHours(int v) => set('podcastCheckHours', v);

  // ---------- reader: type ----------
  String get fontFamily => _get('fontFamily', 'Literata');
  set fontFamily(String v) => set('fontFamily', v);

  double get fontSize => _get('fontSize', 19.0);
  set fontSize(double v) => set('fontSize', v.clamp(11, 40));

  double get lineHeight => _get('lineHeight', 1.6);
  set lineHeight(double v) => set('lineHeight', v);

  double get paragraphSpacing => _get('paragraphSpacing', 0.9);
  set paragraphSpacing(double v) => set('paragraphSpacing', v);

  double get letterSpacing => _get('letterSpacing', 0.0);
  set letterSpacing(double v) => set('letterSpacing', v);

  int get fontWeight => _get('fontWeight', 400);
  set fontWeight(int v) => set('fontWeight', v);

  double get margin => _get('margin', 24.0);
  set margin(double v) => set('margin', v);

  bool get justify => _get('justify', false);
  set justify(bool v) => set('justify', v);

  bool get indentParagraphs => _get('indent', false);
  set indentParagraphs(bool v) => set('indent', v);

  bool get showImages => _get('showImages', true);
  set showImages(bool v) => set('showImages', v);

  // ---------- reader: light ----------
  String get daySurface => _get('daySurface', 'paper');
  set daySurface(String v) => set('daySurface', v);

  String get nightSurface => _get('nightSurface', 'graphite');
  set nightSurface(String v) => set('nightSurface', v);

  bool get night => _get('night', false);
  set night(bool v) => set('night', v);

  bool get nightFollowsSystem => _get('nightFollowsSystem', false);
  set nightFollowsSystem(bool v) => set('nightFollowsSystem', v);

  /// Custom page and ink, used when the surface id is 'custom'.
  Color get customBg => Color(_get('customBg', 0xFFEFE9DD));
  set customBg(Color c) => set('customBg', c.toARGB32());
  Color get customFg => Color(_get('customFg', 0xFF222222));
  set customFg(Color c) => set('customFg', c.toARGB32());

  Surface surfaceFor(bool systemDark) {
    final nightOn = night || (nightFollowsSystem && systemDark);
    final id = nightOn ? nightSurface : daySurface;
    if (id == 'custom') {
      return Surface('custom', 'Custom', customBg, customFg, dark: customBg.computeLuminance() < .35);
    }
    return surfaces.firstWhere((s) => s.id == id, orElse: () => surfaces.first);
  }

  /// Warm amber overlay (0..0.6), a blue-light filter.
  double get warmth => _get('warmth', 0.0);
  set warmth(double v) => set('warmth', v);

  /// Extra dimming beyond the system minimum (0..0.8).
  double get dim => _get('dim', 0.0);
  set dim(double v) => set('dim', v);

  EdgeSide get brightnessEdge => EdgeSide.values[_get('brightnessEdge', 0)];
  set brightnessEdge(EdgeSide v) => set('brightnessEdge', v.index);

  EdgeSide get fontSizeEdge => EdgeSide.values[_get('fontSizeEdge', 3)];
  set fontSizeEdge(EdgeSide v) => set('fontSizeEdge', v.index);

  bool get keepAwake => _get('keepAwake', true);
  set keepAwake(bool v) => set('keepAwake', v);

  bool get immersive => _get('immersive', true);
  set immersive(bool v) => set('immersive', v);

  // ---------- reader: motion ----------
  double get autoScrollSpeed => _get('autoScrollSpeed', 40.0); // px/s
  set autoScrollSpeed(double v) => set('autoScrollSpeed', v.clamp(5, 400));

  bool get autoScrollPauseOnTouch => _get('autoScrollPauseOnTouch', true);
  set autoScrollPauseOnTouch(bool v) => set('autoScrollPauseOnTouch', v);

  bool get tapZones => _get('tapZones', true);
  set tapZones(bool v) => set('tapZones', v);

  /// The volume buttons turn pages while reading.
  bool get volumePaging => _get('volumePaging', true);
  set volumePaging(bool v) => set('volumePaging', v);

  /// Volume up goes forward instead of volume down.
  bool get volumePagingSwapped => _get('volumePagingSwapped', false);
  set volumePagingSwapped(bool v) => set('volumePagingSwapped', v);

  bool get showReaderHud => _get('showReaderHud', true);
  set showReaderHud(bool v) => set('showReaderHud', v);

  bool get showClock => _get('showClock', true);
  set showClock(bool v) => set('showClock', v);

  // ---------- swipe (tiktok) mode ----------
  int get swipeWords => _get('swipeWords', 110);
  set swipeWords(int v) => set('swipeWords', v);

  /// Size swipe cards to fill the screen instead of a fixed word count.
  bool get swipeFit => _get('swipeFit', true);
  set swipeFit(bool v) => set('swipeFit', v);

  double get swipeFontScale => _get('swipeFontScale', 1.25);
  set swipeFontScale(double v) => set('swipeFontScale', v);

  bool get swipeHorizontal => _get('swipeHorizontal', false);
  set swipeHorizontal(bool v) => set('swipeHorizontal', v);

  bool get swipeAuto => _get('swipeAuto', false);
  set swipeAuto(bool v) => set('swipeAuto', v);

  /// Words per minute used by swipe auto-advance.
  int get swipeWpm => _get('swipeWpm', 240);
  set swipeWpm(int v) => set('swipeWpm', v);

  // ---------- listen ----------
  /// Starting a podcast episode or a station from its details opens the full player.
  bool get openPlayerOnPlay => _get('openPlayerOnPlay', true);
  set openPlayerOnPlay(bool v) => set('openPlayerOnPlay', v);

  /// How a show's episodes are ordered unless that show has its own order:
  /// an [EpisodeSort] name (newest, oldest, az, za).
  String get episodeSort => _get('episodeSort', 'newest');
  set episodeSort(String v) => set('episodeSort', v);

  double get ttsRate => _get('ttsRate', 0.5);
  set ttsRate(double v) => set('ttsRate', v);

  double get ttsPitch => _get('ttsPitch', 1.0);
  set ttsPitch(double v) => set('ttsPitch', v);

  /// Who reads aloud: 'device' (default), 'addis' or 'elevenlabs'.
  String get ttsEngine => _get('ttsEngine', 'device');
  set ttsEngine(String v) => set('ttsEngine', v);

  /// The chosen voice per engine: id, display name and language. Empty means the engine's default.
  ({String id, String name, String lang}) ttsVoice(String engine) =>
      (id: _get('ttsVoice.$engine', ''), name: _get('ttsVoiceName.$engine', ''), lang: _get('ttsVoiceLang.$engine', ''));
  void setTtsVoice(String engine, {required String id, required String name, String lang = ''}) {
    _v['ttsVoice.$engine'] = id;
    _v['ttsVoiceName.$engine'] = name;
    set('ttsVoiceLang.$engine', lang);
  }

  /// ElevenLabs speech model.
  String get elevenModel => _get('elevenModel', 'eleven_flash_v2_5');
  set elevenModel(String v) => set('elevenModel', v);

  // ---------- pdf ----------
  bool get pdfOriginal => _get('pdfOriginal', false);
  set pdfOriginal(bool v) => set('pdfOriginal', v);

  // ---------- ai ----------
  String get aiModel => _get('aiModel', 'google:gemini-2.5-flash');
  set aiModel(String v) => set('aiModel', v);

  String get aiLevel => _get('aiLevel', 'clear');
  set aiLevel(String v) => set('aiLevel', v);

  String get aiLanguage => _get('aiLanguage', 'English');
  set aiLanguage(String v) => set('aiLanguage', v);

  bool get aiSpoilerGuard => _get('aiSpoilerGuard', true);
  set aiSpoilerGuard(bool v) => set('aiSpoilerGuard', v);

  // ---------- quote cards ----------
  /// A background of your own for share cards; null uses the card style's.
  Color? get cardBg {
    final v = _get('cardBg', 0);
    return v == 0 ? null : Color(v);
  }

  set cardBg(Color? c) => set('cardBg', c?.toARGB32() ?? 0);

  int get quoteStyle => _get('quoteStyle', 0);
  set quoteStyle(int v) => set('quoteStyle', v);

  /// The "ALEXANDRIA / KIND" line on share cards.
  bool get quoteBrand => _get('quoteBrand', true);
  set quoteBrand(bool v) => set('quoteBrand', v);

  static const readerKeys = [
    'fontFamily', 'fontSize', 'lineHeight', 'paragraphSpacing', 'letterSpacing', 'fontWeight', //
    'margin', 'justify', 'indent', 'showImages',
  ];
}
