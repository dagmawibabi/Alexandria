import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/color_picker.dart';
import '../core/settings.dart';
import '../core/theme.dart';
import '../core/ui.dart';
import '../models/podcast.dart';
import '../services/ai.dart';
import '../services/backup.dart';
import '../services/podcasts.dart';
import '../services/speech.dart';
import 'ai_sheets.dart';
import 'listen_sheet.dart';
import 'reader/reader_sheets.dart';
import 'stats_screen.dart';
import 'widgets_screen.dart';

/// The settings index: short groups of rows, each opening its own page.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: ListenableBuilder(
        listenable: Settings.i,
        builder: (context, _) {
          final s = Settings.i;
          final look = [if (s.zen) 'Zen', if (s.mono) 'Monochrome', switch (s.themeMode) { ThemeMode.light => 'Light', ThemeMode.dark => 'Dark', _ => 'System theme' }].join(' · ');
          return ListView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 32), children: [
            const Kicker('System / configuration'),
            Text(s.zen ? 'Settings' : 'Config', style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -1.2, height: 1)),
            const _Group('General'),
            _Row(Icons.palette_outlined, 'Appearance', look, () => _open(context, 'Appearance', const _Appearance())),
            _Row(Icons.grid_view_sharp, 'Library', s.libraryGrid ? 'Grid · ${s.gridColumns} columns' : 'List', () => _open(context, 'Library', const _Library())),
            _Row(Icons.flag_outlined, 'Goals', '${s.dailyGoalMinutes} min a day · ${s.yearlyGoalBooks} books a year', () => _open(context, 'Goals', const GoalControls())),
            _Row(Icons.widgets_outlined, 'Home-screen widgets', 'Your stats on the home screen, in your style', () => openStatWidgets(context)),
            const _Group('Reading'),
            _Row(Icons.text_fields_sharp, 'Type', '${s.fontFamily} · ${s.fontSize.round()} pt', () => _open(context, 'Type', const TypeControls())),
            _Row(Icons.contrast_sharp, 'Light & surface', 'Page colours, night mode, warmth', () => _open(context, 'Light & surface', const LightControls())),
            _Row(Icons.swipe_sharp, 'Motion & gestures', 'Auto-scroll, swipe cards, tap zones', () => _open(context, 'Motion & gestures', const MotionControls(showListen: false))),
            const _Group('Listening'),
            _Row(Icons.record_voice_over_outlined, 'Read-aloud voice', Speech.summary, () => _open(context, 'Read-aloud voice', const ListenPanel())),
            _Row(
              Icons.podcasts_sharp,
              'Player & podcasts',
              [
                s.openPlayerOnPlay ? 'Full player on play' : 'Mini player',
                EpisodeSort.parse(s.episodeSort).label,
                s.podcastAlerts ? 'Alerts every ${s.podcastCheckHours} h' : 'Alerts off',
              ].join(' · '),
              () => _open(context, 'Player & podcasts', const _PlayerAndPodcasts()),
            ),
            const _Group('Assistant'),
            _Row(Icons.auto_awesome_outlined, 'AI companion', Ai.configured ? Ai.model : 'Not connected', () => _open(context, 'AI companion', const _AiPage())),
            const _Group('Your data'),
            _Row(Icons.backup_outlined, 'Backup & restore', 'Export or import everything as JSON', () => _open(context, 'Backup & restore', const _Data())),
          ]);
        },
      ),
    );
  }

  void _open(BuildContext context, String title, Widget body) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (ctx) => Scaffold(
        appBar: AppBar(title: AppTitle(title)),
        body: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 40), children: [body]),
      ),
    ));
  }
}

class _Group extends StatelessWidget {
  const _Group(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.fromLTRB(2, 24, 0, 8), child: Label(title, color: Tokens.of(context).muted, weight: FontWeight.w600));
}

class _Row extends StatelessWidget {
  const _Row(this.icon, this.title, this.summary, this.onTap);
  final IconData icon;
  final String title;
  final String summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Panel(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          Icon(icon, size: 20, color: t.accent),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              const SizedBox(height: 2),
              Text(summary, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.muted, fontSize: 12.5)),
            ]),
          ),
          Icon(Icons.chevron_right_sharp, color: t.muted),
        ]),
      ),
    );
  }
}

class _Appearance extends StatelessWidget {
  const _Appearance();

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return ListenableBuilder(
      listenable: Settings.i,
      builder: (context, _) {
        final s = Settings.i;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ToggleRow(
            label: 'Zen mode',
            hint: 'A calm, modern, minimal design everywhere, instead of the industrial look.',
            value: s.zen,
            onChanged: (v) => s.zen = v,
          ),
          ToggleRow(
            label: 'Monochrome',
            hint: 'Black, white and greys only. Accents follow the ink colour and covers go grey.',
            value: s.mono,
            onChanged: (v) => s.mono = v,
          ),
          const SizedBox(height: 10),
          const Label('Theme'),
          const SizedBox(height: 8),
          Segmented<ThemeMode>(values: ThemeMode.values, labels: const ['System', 'Light', 'Dark'], value: s.themeMode, onChanged: (v) => s.themeMode = v),
          const SizedBox(height: 18),
          Row(children: [
            const Label('Accent colour'),
            const Spacer(),
            Label(s.mono ? 'Off in monochrome' : (accentNames[s.accent.toARGB32()] ?? 'Custom'), color: t.accent, weight: FontWeight.w600),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in accents)
              GestureDetector(
                onTap: () {
                  haptic();
                  s.accent = c;
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(color: c, borderRadius: t.br, border: Border.all(color: s.accent == c ? t.ink : t.line, width: 2)),
                  child: s.accent == c ? Icon(Icons.check_sharp, size: 18, color: c.computeLuminance() > .5 ? Colors.black : Colors.white) : null,
                ),
              ),
          ]),
          const SizedBox(height: 6),
          ColorRow(label: 'Custom colour', color: s.accent, onChanged: (c) => s.accent = c),
          const SizedBox(height: 10),
          // Live preview of the accent on real controls.
          Row(children: [
            Expanded(child: PrimaryButton('Preview', icon: Icons.auto_awesome_outlined, onTap: () {})),
            const SizedBox(width: 10),
            Toggle(value: true, onChanged: (_) {}),
            const SizedBox(width: 10),
            Tag('Tag', color: t.accent, filled: true),
          ]),
          const SizedBox(height: 18),
          if (!s.zen) ...[
            SliderRow(label: 'Corner radius', value: s.radius, min: 0, max: 16, divisions: 16, format: (v) => v.round().toString(), onChanged: (v) => s.radius = v),
            const SizedBox(height: 6),
          ],
          const Label('Interface typeface'),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [for (final f in uiFonts) Tag(f, filled: s.uiFont == f, onTap: () => s.uiFont = f)]),
          const SizedBox(height: 8),
          if (!s.zen) ToggleRow(label: 'Dot-grid backdrop', value: s.dotGrid, onChanged: (v) => s.dotGrid = v),
          ToggleRow(label: 'Haptics', value: s.haptics, onChanged: (v) => s.haptics = v),
        ]);
      },
    );
  }
}

class _Library extends StatelessWidget {
  const _Library();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Settings.i,
      builder: (context, _) {
        final s = Settings.i;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Label('Show books as', size: 12),
          const SizedBox(height: 8),
          Segmented<bool>(values: const [true, false], labels: const ['Grid', 'List'], value: s.libraryGrid, onChanged: (v) => s.libraryGrid = v),
          const SizedBox(height: 14),
          if (s.libraryGrid) SettingSlider(title: 'Columns', hint: 'How many books fit across the screen.', value: s.gridColumns, min: 2, max: 5, onChanged: (v) => s.gridColumns = v),
          SettingToggle(title: 'Progress on covers', hint: 'A thin bar along the bottom of each cover.', value: s.showProgressOnCovers, onChanged: (v) => s.showProgressOnCovers = v),
          SettingToggle(title: 'Auto-fetch covers & info', hint: 'Looks new books up in Open Library and Google Books when you add them.', value: s.autoFetchMetadata, onChanged: (v) => s.autoFetchMetadata = v),
        ]);
      },
    );
  }
}

/// The player, episode order and new-episode alerts, on one page.
class _PlayerAndPodcasts extends StatelessWidget {
  const _PlayerAndPodcasts();

  @override
  Widget build(BuildContext context) {
    Widget heading(String title, {bool first = false}) => Padding(padding: EdgeInsets.fromLTRB(2, first ? 4 : 28, 0, 10), child: Label(title, color: Tokens.of(context).muted, weight: FontWeight.w600));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      heading('Player', first: true),
      const _Player(),
      heading('Episode order'),
      const _EpisodeOrder(),
      heading('New-episode alerts'),
      const _PodcastAlerts(),
    ]);
  }
}

class _Player extends StatelessWidget {
  const _Player();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Settings.i,
      builder: (context, _) => SettingToggle(
        title: 'Open the full player on play',
        hint: 'When you start a podcast episode, or a station from its details. Off, it plays in the mini player and you stay where you are.',
        value: Settings.i.openPlayerOnPlay,
        onChanged: (v) => Settings.i.openPlayerOnPlay = v,
      ),
    );
  }
}

/// The default order of a show's episodes, and resetting shows to it.
class _EpisodeOrder extends StatelessWidget {
  const _EpisodeOrder();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([Settings.i, Podcasts.i]),
      builder: (context, _) {
        final t = Tokens.of(context);
        final s = Settings.i;
        final own = Podcasts.i.showSorts.length;
        final current = EpisodeSort.parse(s.episodeSort);
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('How a show’s episodes are listed. A show you set an order on yourself, from the chip above its episodes, keeps its own.', style: TextStyle(color: t.muted, height: 1.4)),
          const SizedBox(height: 14),
          Segmented<EpisodeSort>(values: EpisodeSort.values, labels: [for (final v in EpisodeSort.values) v.short], value: current, onChanged: (v) => s.episodeSort = v.name),
          const SizedBox(height: 22),
          Panel(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Apply to every show', style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600)),
              const SizedBox(height: 3),
              Text(own == 0 ? 'Every show already follows this order.' : '${own == 1 ? 'One show has' : '$own shows have'} an order of their own. This puts them back on “${current.label}”.', style: TextStyle(color: t.muted, fontSize: 13.5, height: 1.3)),
              if (own > 0) ...[
                const SizedBox(height: 12),
                PrimaryButton('Apply to all shows', icon: Icons.done_all_sharp, onTap: () async {
                  if (await confirm(context, 'Apply to all shows', 'Every show will list its episodes ${current.label.toLowerCase()}. Shows you ordered yourself lose that choice.')) Podcasts.i.clearSorts();
                }),
              ],
            ]),
          ),
        ]);
      },
    );
  }
}

class _PodcastAlerts extends StatefulWidget {
  const _PodcastAlerts();

  @override
  State<_PodcastAlerts> createState() => _PodcastAlertsState();
}

class _PodcastAlertsState extends State<_PodcastAlerts> {
  bool _checking = false;
  String? _result;

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _result = null;
    });
    final n = await Podcasts.i.checkNow().catchError((_) => -1);
    if (!mounted) return;
    setState(() {
      _checking = false;
      _result = n < 0 ? 'Couldn\'t check. Are you online?' : (n == 0 ? 'No new episodes.' : '$n new episode${n == 1 ? '' : 's'}: see your notifications.');
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return ListenableBuilder(
      listenable: Settings.i,
      builder: (context, _) {
        final s = Settings.i;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SettingToggle(
            title: 'Alert me to new episodes',
            hint: 'Checks your subscribed shows even when the app is closed.',
            value: s.podcastAlerts,
            onChanged: (v) {
              s.podcastAlerts = v;
              Podcasts.i.syncBackgroundCheck();
            },
          ),
          if (s.podcastAlerts)
            SettingSlider(
              title: 'Check every',
              hint: 'Android picks the exact moment to save battery, so it can run later than this.',
              value: s.podcastCheckHours,
              min: 1,
              max: 24,
              unit: 'hours',
              onChanged: (v) {
                s.podcastCheckHours = v;
                Podcasts.i.syncBackgroundCheck();
              },
            ),
          PrimaryButton(_checking ? 'Checking…' : 'Check now', ghost: true, icon: Icons.refresh_sharp, expand: true, onTap: _checking ? null : _check),
          if (_result != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_result!, style: TextStyle(color: t.muted, height: 1.4))),
        ]);
      },
    );
  }
}

class _AiPage extends StatelessWidget {
  const _AiPage();

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return ListenableBuilder(
      listenable: Settings.i,
      builder: (context, _) {
        final s = Settings.i;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const AiKeysPanel(),
          Panel(
            onTap: () => pickModel(context),
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              const Label('Model'),
              const SizedBox(width: 12),
              Expanded(child: Text(Ai.model, textAlign: TextAlign.end, maxLines: 1, overflow: TextOverflow.ellipsis, style: mono(context, size: 11, color: t.ink, spacing: 0))),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right_sharp, color: t.muted),
            ]),
          ),
          const SizedBox(height: 14),
          const Label('Explanation level'),
          const SizedBox(height: 8),
          Segmented<String>(values: const ['simple', 'clear', 'expert'], labels: const ['Simple', 'Clear', 'Expert'], value: s.aiLevel, onChanged: (v) => s.aiLevel = v),
          const SizedBox(height: 14),
          const Label('Answer language'),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final l in const ['English', 'Spanish', 'French', 'German', 'Amharic', 'Arabic', 'Chinese', 'Japanese'])
              Tag(l, filled: s.aiLanguage == l, onTap: () => s.aiLanguage = l),
          ]),
          const SizedBox(height: 6),
          ToggleRow(label: 'Spoiler guard', hint: 'AI never reveals beyond your progress', value: s.aiSpoilerGuard, onChanged: (v) => s.aiSpoilerGuard = v),
        ]);
      },
    );
  }
}

class _Data extends StatefulWidget {
  const _Data();

  @override
  State<_Data> createState() => _DataState();
}

class _DataState extends State<_Data> {
  bool _busy = false;
  String? _result;

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final dir = await getTemporaryDirectory();
      final now = DateTime.now();
      final f = File(p.join(dir.path, 'alexandria-backup-${now.year}-${pad(now.month)}-${pad(now.day)}.json'));
      await f.writeAsString(const JsonEncoder.withIndent(' ').convert(Backup.export()));
      await SharePlus.instance.share(ShareParams(files: [XFile(f.path, mimeType: 'application/json')], subject: 'Alexandria backup'));
    } catch (e) {
      if (mounted) toast(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    // Any file type: Android's picker doesn't reliably recognise .json.
    final files = await FilePicker.pickFiles(dialogTitle: 'Choose an Alexandria backup');
    final path = files.firstOrNull?.path;
    if (path == null || !mounted) return;
    setState(() {
      _busy = true;
      _result = null;
    });
    try {
      final j = await Backup.read(path);
      if (!mounted) return;
      int count(String k) => (j[k] as List?)?.length ?? 0;
      final date = DateTime.tryParse('${j['exportedAt'] ?? ''}');
      final ok = await confirm(
        context,
        'Import backup',
        '${date == null ? 'This backup' : 'From ${date.day}.${date.month}.${date.year}'}: ${count('books')} books, ${count('audiobooks')} audiobooks.\n\nThis merges with what\'s here. Nothing is deleted, and the most recently used copy of each item wins. Your settings are replaced by the backup\'s.',
      );
      if (!ok || !mounted) return;
      final r = await Backup.restore(j);
      if (!mounted) return;
      setState(() {
        _result = [
          'Added ${r.books} books, ${r.audiobooks} audiobooks, ${r.shows} shows, ${r.episodes} episodes and ${r.notes} highlights or bookmarks.',
          if (r.missingBooks > 0) '${r.missingBooks} books weren\'t added because their files aren\'t on this device. Add the same files again and their highlights and progress stats reconnect.',
          if (r.missingAudiobooks > 0) '${r.missingAudiobooks} audiobooks weren\'t added because their audio files aren\'t on this device.',
        ].join('\n\n');
      });
    } catch (e) {
      if (mounted) setState(() => _result = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('A backup holds your library, progress, highlights, bookmarks, notes, ratings, folders, stats, audiobook shelf, podcast subscriptions and settings.', style: TextStyle(height: 1.45, color: t.ink.withValues(alpha: .85))),
      const SizedBox(height: 8),
      Text('It doesn\'t include the book and audio files themselves, or your API keys.', style: TextStyle(height: 1.45, color: t.muted)),
      const SizedBox(height: 18),
      PrimaryButton('Export backup', icon: Icons.save_alt_sharp, expand: true, onTap: _busy ? null : _export),
      const SizedBox(height: 8),
      PrimaryButton('Import backup', ghost: true, icon: Icons.file_open_outlined, expand: true, onTap: _busy ? null : _import),
      if (_busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
      if (_result != null) ...[
        const SizedBox(height: 14),
        Panel(padding: const EdgeInsets.all(14), child: Text(_result!, style: const TextStyle(height: 1.45))),
      ],
      const SizedBox(height: 28),
      const Label('Adding books'),
      const SizedBox(height: 8),
      Text('Open PDF, EPUB or DOCX files from any app (Files, Telegram, WhatsApp, Gmail, browsers) and pick "Read in Alexandria", or share them to Alexandria.', style: TextStyle(color: t.muted, height: 1.45, fontSize: 13)),
    ]);
  }
}
