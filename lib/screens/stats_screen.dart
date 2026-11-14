import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../core/settings.dart';
import '../core/theme.dart';
import '../core/ui.dart';
import '../models/annotations.dart';
import '../models/book.dart';
import '../services/audio.dart';
import '../services/library.dart';
import '../services/podcasts.dart';
import '../services/radio.dart';
import 'library_screen.dart';
import 'player_screen.dart';
import 'podcasts_view.dart';
import 'usage_section.dart';
import 'widgets_screen.dart';

void openStats(BuildContext context) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const StatsScreen()));

/// Time and totals across books, audiobooks and podcasts.
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  /// 'all', 'books', 'audiobooks' or 'podcasts'.
  String _scope = 'all';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: AppTitle('Stats'), actions: [
        if (kMobile) IconButton(tooltip: 'Home-screen widgets', onPressed: () => openStatWidgets(context), icon: const Icon(Icons.widgets_outlined)),
      ]),
      body: PageWidth(child: ListenableBuilder(
        listenable: Listenable.merge([Library.i, Settings.i, AudioLibrary.i, Podcasts.i]),
        builder: (context, _) => _Body(lib: Library.i, scope: _scope, onScope: (v) => setState(() => _scope = v)),
      )),
    );
  }
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

bool _inScope(ReadingSession x, String scope) => switch (scope) {
      'books' => !x.listening,
      'audiobooks' => x.mode == 'audiobook',
      'podcasts' => x.mode == 'podcast' || x.mode == 'radio',
      _ => true,
    };

class _Body extends StatelessWidget {
  const _Body({required this.lib, required this.scope, required this.onScope});
  final Library lib;
  final String scope;
  final ValueChanged<String> onScope;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final s = Settings.i;
    final audio = AudioLibrary.i;
    final pods = Podcasts.i;
    final sessions = lib.sessions.where((x) => _inScope(x, scope)).toList();
    final now = DateTime.now();
    final today = _day(now);

    final perDay = <DateTime, int>{};
    final perHour = List<int>.filled(24, 0);
    for (final x in sessions) {
      perDay.update(_day(x.start), (v) => v + x.seconds, ifAbsent: () => x.seconds);
      perHour[x.start.hour] += x.seconds;
    }
    final total = sessions.fold(0, (a, x) => a + x.seconds);
    // Speed only means anything for reading: listening has no word count.
    final reading = lib.sessions.where((x) => !x.listening).toList();
    final readSecs = reading.fold(0, (a, x) => a + x.seconds);
    final words = reading.fold(0, (a, x) => a + x.words);
    final wpm = readSecs > 120 ? (words / (readSecs / 60)).round() : 0;
    final bookSecs = readSecs;
    final audioSecs = lib.sessions.where((x) => x.mode == 'audiobook').fold(0, (a, x) => a + x.seconds);
    final podSecs = lib.sessions.where((x) => x.mode == 'podcast' || x.mode == 'radio').fold(0, (a, x) => a + x.seconds);
    final todaySecs = perDay[today] ?? 0;
    final weekSecs = [for (var i = 0; i < 7; i++) perDay[today.subtract(Duration(days: i))] ?? 0].fold(0, (a, b) => a + b);

    // streaks (a day counts with at least a minute)
    var streak = 0;
    for (var d = perDay.containsKey(today) ? today : today.subtract(const Duration(days: 1)); (perDay[d] ?? 0) >= 60; d = d.subtract(const Duration(days: 1))) {
      streak++;
    }
    var best = 0, run = 0;
    final days = perDay.keys.toList()..sort();
    DateTime? prev;
    for (final d in days) {
      if ((perDay[d] ?? 0) < 60) continue;
      run = (prev != null && d.difference(prev).inDays == 1) ? run + 1 : 1;
      best = math.max(best, run);
      prev = d;
    }

    final finishedThisYear = lib.books.where((b) => b.status == ReadStatus.finished && (b.finishedAt?.year ?? 0) == now.year).length;
    final finished = lib.books.where((b) => b.status == ReadStatus.finished).length;
    final audioDone = audio.books.where((b) => b.finished).length;
    final played = pods.states.values.where((x) => x.played).length;
    final avgSession = sessions.isEmpty ? 0 : total ~/ sessions.length;
    final audioNotes = audio.books.fold(0, (a, b) => a + b.mark.notes.length);
    final podNotes = pods.showMarks.values.fold(0, (a, m) => a + m.notes.length) + pods.states.values.fold(0, (a, x) => a + x.mark.notes.length);
    final audioFav = audio.books.where((b) => b.mark.favorite).length;
    final podFav = pods.showMarks.values.where((m) => m.favorite).length + pods.states.values.where((x) => x.mark.favorite).length;
    final audioSaved = audio.books.where((b) => b.tracks.any((x) => !x.remote)).length;

    final perItem = <String, int>{};
    for (final x in sessions) {
      perItem.update(x.bookId, (v) => v + x.seconds, ifAbsent: () => x.seconds);
    }
    final top = perItem.entries.where((e) => _known(e.key)).toList()..sort((a, b) => b.value.compareTo(a.value));

    // Books break down by how you read; everything else by what it was.
    final split = <String, int>{};
    if (scope == 'books') {
      for (final x in sessions) {
        split.update(x.mode, (v) => v + x.seconds, ifAbsent: () => x.seconds);
      }
    } else if (scope == 'all') {
      if (bookSecs > 0) split['Books'] = bookSecs;
      if (audioSecs > 0) split['Audiobooks'] = audioSecs;
      if (podSecs > 0) split['Podcasts'] = podSecs;
    }

    final tiles = switch (scope) {
      'books' => [
          _Tile('Total time', fmtDuration(total), Icons.timer_outlined),
          _Tile('Avg speed', wpm > 0 ? '$wpm wpm' : '—', Icons.speed_sharp),
          _Tile('Finished', '$finished', Icons.done_all_sharp),
          _Tile('Sessions', '${sessions.length}', Icons.stacked_bar_chart_sharp),
          _Tile('Avg session', fmtDuration(avgSession), Icons.av_timer_sharp),
          _Tile('Words read', words > 9999 ? '${(words / 1000).toStringAsFixed(1)}k' : '$words', Icons.notes_sharp),
          _Tile('Highlights', '${lib.highlights.length}', Icons.border_color_outlined),
          _Tile('Library', '${lib.books.length} vols', Icons.inventory_2_outlined),
        ],
      'audiobooks' => [
          _Tile('Listened', fmtDuration(total), Icons.headphones_outlined),
          _Tile('On shelf', '${audio.books.length}', Icons.inventory_2_outlined),
          _Tile('Finished', '$audioDone', Icons.done_all_sharp),
          _Tile('Sessions', '${sessions.length}', Icons.stacked_bar_chart_sharp),
          _Tile('Avg session', fmtDuration(avgSession), Icons.av_timer_sharp),
          _Tile('Notes', '$audioNotes', Icons.edit_note_sharp),
          _Tile('Favourites', '$audioFav', Icons.favorite_border_sharp),
          _Tile('Offline', '$audioSaved', Icons.download_done_sharp),
        ],
      'podcasts' => [
          _Tile('Listened', fmtDuration(total), Icons.podcasts_sharp),
          _Tile('Shows', '${pods.subscriptions.length}', Icons.inventory_2_outlined),
          _Tile('Episodes played', '$played', Icons.done_all_sharp),
          _Tile('In progress', '${pods.inProgress.length}', Icons.pending_outlined),
          _Tile('Avg session', fmtDuration(avgSession), Icons.av_timer_sharp),
          _Tile('Notes', '$podNotes', Icons.edit_note_sharp),
          _Tile('Favourites', '$podFav', Icons.favorite_border_sharp),
          _Tile('Offline', '${pods.downloaded.length}', Icons.download_done_sharp),
        ],
      _ => [
          _Tile('Total time', fmtDuration(total), Icons.timer_outlined),
          _Tile('Reading', fmtDuration(bookSecs), Icons.menu_book_sharp),
          _Tile('Audiobooks', fmtDuration(audioSecs), Icons.headphones_outlined),
          _Tile('Podcasts', fmtDuration(podSecs), Icons.podcasts_sharp),
          _Tile('Books finished', '$finished', Icons.done_all_sharp),
          _Tile('Audiobooks finished', '$audioDone', Icons.done_all_sharp),
          _Tile('Episodes played', '$played', Icons.done_all_sharp),
          _Tile('Sessions', '${sessions.length}', Icons.stacked_bar_chart_sharp),
        ],
    };

    return ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 40), children: [
        Segmented<String>(values: const ['all', 'books', 'audiobooks', 'podcasts'], labels: const ['All', 'Books', 'Audio', 'Podcasts'], value: scope, onChanged: onScope),
        const SizedBox(height: 14),

        Panel(
          onTap: () => showGoals(context, only: 'daily'),
          child: Row(children: [
            SizedBox(width: 108, height: 108, child: CustomPaint(painter: _Ring(todaySecs / (s.dailyGoalMinutes * 60), t), child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('${todaySecs ~/ 60}', style: mono(context, size: 28, color: t.ink, weight: FontWeight.w700, spacing: -1)),
              Label('/ ${s.dailyGoalMinutes} min', size: 9),
            ])))),
            const SizedBox(width: 20),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Label('Today', color: t.accent),
                const SizedBox(height: 6),
                Text(todaySecs >= s.dailyGoalMinutes * 60 ? 'Goal reached.' : '${math.max(0, s.dailyGoalMinutes - todaySecs ~/ 60)} min to goal', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                Row(children: [
                  Icon(Icons.local_fire_department_sharp, size: 16, color: streak > 0 ? t.accent : t.muted),
                  const SizedBox(width: 6),
                  Expanded(child: Label('$streak day streak · best $best')),
                ]),
                const SizedBox(height: 4),
                Label('This week ${fmtDuration(weekSecs)}'),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.9,
          children: tiles,
        ),

        const SectionHeader('01', 'Last 14 days', padding: EdgeInsets.fromLTRB(0, 28, 0, 12)),
        Panel(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 10),
          child: SizedBox(
            height: 150,
            child: _Bars(
              values: [for (var i = 13; i >= 0; i--) (perDay[today.subtract(Duration(days: i))] ?? 0) / 60],
              labels: [for (var i = 13; i >= 0; i--) 'MTWTFSS'[today.subtract(Duration(days: i)).weekday - 1]],
              goal: s.dailyGoalMinutes.toDouble(),
            ),
          ),
        ),

        const SectionHeader('02', 'Time of day', padding: EdgeInsets.fromLTRB(0, 28, 0, 12)),
        Panel(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            Row(children: [
              for (var h = 0; h < 24; h++)
                Expanded(
                  child: Container(
                    height: 28,
                    margin: const EdgeInsets.only(right: 2),
                    decoration: BoxDecoration(
                      color: perHour.reduce(math.max) == 0 ? t.line : Color.lerp(t.line, t.accent, perHour[h] / perHour.reduce(math.max)),
                      borderRadius: t.zen ? BorderRadius.circular(3) : null,
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: 6),
            const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Label('00', size: 8.5), Label('06', size: 8.5), Label('12', size: 8.5), Label('18', size: 8.5), Label('23', size: 8.5)]),
          ]),
        ),

        SectionHeader(
          '03',
          'Goals',
          padding: const EdgeInsets.fromLTRB(0, 28, 0, 12),
          trailing: Tag('Set goals', color: t.accent, onTap: () => showGoals(context)),
        ),
        Panel(
          child: Column(children: [
            _GoalBar(id: 'daily', label: 'Today', value: lib.sessions.where((x) => _day(x.start) == today).fold(0, (a, x) => a + x.seconds) ~/ 60, goal: s.dailyGoalMinutes, unit: 'min'),
            if (scope == 'all' || scope == 'books') _GoalBar(id: 'books', label: 'Books in ${now.year}', value: finishedThisYear, goal: s.yearlyGoalBooks),
            if (scope == 'all' || scope == 'audiobooks')
              _GoalBar(id: 'audio', label: 'Audiobooks in ${now.year}', value: audio.books.where((b) => b.finished && (b.finishedAt ?? b.lastPlayedAt)?.year == now.year).length, goal: s.yearlyGoalAudiobooks),
            if (scope == 'all' || scope == 'podcasts')
              _GoalBar(id: 'episodes', label: 'Episodes this week', value: pods.states.values.where((x) => x.played && now.difference(x.updatedAt).inDays < 7).length, goal: s.weeklyGoalEpisodes),
          ]),
        ),

        // AI answers and read-aloud belong with reading, not audiobooks or podcasts.
        if (scope == 'all' || scope == 'books') const UsageSection(),
        if (split.isNotEmpty) ...[
          SectionHeader('04', scope == 'books' ? 'By mode' : 'By kind', padding: const EdgeInsets.fromLTRB(0, 28, 0, 12)),
          Panel(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              ClipRRect(
                borderRadius: t.br,
                child: Row(children: [
                  for (final (i, e) in split.entries.indexed)
                    Expanded(flex: math.max(1, e.value), child: Container(height: 14, color: [t.accent, t.ink, t.muted, t.line][i % 4])),
                ]),
              ),
              const SizedBox(height: 10),
              Wrap(spacing: 14, runSpacing: 6, children: [
                for (final (i, e) in split.entries.indexed)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 8, height: 8, color: [t.accent, t.ink, t.muted, t.line][i % 4]),
                    const SizedBox(width: 6),
                    Label('${e.key} ${fmtDuration(e.value)}'),
                  ]),
              ]),
            ]),
          ),
        ],

        SectionHeader('05', scope == 'all' ? 'Most time' : (scope == 'books' ? 'Most read' : 'Most listened'), padding: const EdgeInsets.fromLTRB(0, 28, 0, 12)),
        if (top.isEmpty) const Label('Read or listen and numbers appear here.'),
        for (final e in top.take(8)) _TopRow(id: e.key, seconds: e.value, max: top.first.value, sessions: lib.sessions.where((x) => x.bookId == e.key).toList()),
      ]);
  }
}

/// Whether a session's subject can still be shown.
bool _known(String id) => Library.i.byId(id) != null || AudioLibrary.i.byId(id) != null || id.startsWith('pod:') || id.startsWith('radio:');

/// One goal's progress. Tap it to change the goal.
class _GoalBar extends StatelessWidget {
  const _GoalBar({required this.id, required this.label, required this.value, required this.goal, this.unit = ''});
  final String id;
  final String label;
  final int value;
  final int goal;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Tap(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        haptic();
        showGoals(context, only: id);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5))),
            Text('$value / $goal${unit.isEmpty ? '' : ' $unit'}', style: TextStyle(color: value >= goal ? t.accent : t.ink, fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right_sharp, size: 18, color: t.muted),
          ]),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(t.zen ? 3 : 0),
            child: LinearProgressIndicator(value: goal == 0 ? 0 : (value / goal).clamp(0.0, 1.0), minHeight: 7),
          ),
        ]),
      ),
    );
  }
}

/// The goal settings, shared by Stats and Settings. With [only], just that goal.
class GoalControls extends StatelessWidget {
  const GoalControls({super.key, this.only});

  /// 'daily', 'books', 'audio' or 'episodes'.
  final String? only;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Settings.i,
      builder: (context, _) {
        final s = Settings.i;
        bool show(String id) => only == null || only == id;
        return Column(children: [
          if (show('daily'))
            SettingSlider(title: 'Daily time', hint: 'Reading and listening both count.', value: s.dailyGoalMinutes, min: 5, max: 240, step: 5, unit: 'min', onChanged: (v) => s.dailyGoalMinutes = v),
          if (show('books')) SettingSlider(title: 'Books a year', hint: 'Books you finish reading.', value: s.yearlyGoalBooks, min: 1, max: 120, onChanged: (v) => s.yearlyGoalBooks = v),
          if (show('audio')) SettingSlider(title: 'Audiobooks a year', hint: 'Audiobooks you finish listening to.', value: s.yearlyGoalAudiobooks, min: 1, max: 120, onChanged: (v) => s.yearlyGoalAudiobooks = v),
          if (show('episodes')) SettingSlider(title: 'Episodes a week', hint: 'Podcast episodes you finish.', value: s.weeklyGoalEpisodes, min: 1, max: 50, onChanged: (v) => s.weeklyGoalEpisodes = v),
        ]);
      },
    );
  }
}

/// Edit one goal, or all of them.
Future<void> showGoals(BuildContext context, {String? only}) {
  return showSheet(context, builder: (ctx) {
    final t = Tokens.of(ctx);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(only == null ? 'Your goals' : 'Set this goal', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
          if (only != null)
            Tap(
              onTap: () {
                Navigator.pop(ctx);
                showGoals(context);
              },
              child: Label('All goals', color: t.accent, weight: FontWeight.w600),
            ),
        ]),
        const SizedBox(height: 14),
        GoalControls(only: only),
      ]),
    );
  });
}

class _Tile extends StatelessWidget {
  const _Tile(this.k, this.v, this.icon);
  final String k;
  final String v;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: t.surface, borderRadius: t.br, border: t.zen ? null : Border.all(color: t.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Row(children: [Icon(icon, size: 14, color: t.muted), const SizedBox(width: 6), Expanded(child: Label(k, size: 9))]),
        FittedBox(fit: BoxFit.scaleDown, child: Text(v, style: mono(context, size: 21, color: t.ink, weight: FontWeight.w700, spacing: -.5))),
      ]),
    );
  }
}

/// One book, audiobook or show with its share of the time.
class _TopRow extends StatelessWidget {
  const _TopRow({required this.id, required this.seconds, required this.max, required this.sessions});
  final String id;
  final int seconds;
  final int max;
  final List<ReadingSession> sessions;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final book = Library.i.byId(id);
    final audio = AudioLibrary.i.byId(id);
    final feed = id.startsWith('pod:') ? id.substring(4) : null;
    final show = feed == null ? null : Podcasts.i.cached(feed);
    final station = id.startsWith('radio:') ? RadioDirectory.i.stationFor(id.substring(6)) : null;
    final title = book?.title ?? audio?.title ?? show?.title ?? station?.name ?? sessions.last.label ?? 'Podcast';
    final words = sessions.fold(0, (a, s) => a + s.words);
    final wpm = book != null && seconds > 60 ? (words / (seconds / 60)).round() : 0;
    final detail = [
      fmtDuration(seconds),
      '${sessions.length} sessions',
      if (wpm > 0) '$wpm wpm',
      if (book != null) '${(book.progress * 100).round()}%',
      if (audio != null) '${(audio.progress * 100).round()}%',
    ].join(' · ');
    return Tap(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (book != null) {
          openDetail(context, book);
        } else if (audio != null) {
          playAudiobook(context, audio);
        } else if (feed != null && feed.startsWith('http')) {
          openPodcast(context, feedUrl: feed);
        } else if (station != null) {
          RadioDirectory.i.play(station);
        }
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          SizedBox(
            width: 40,
            child: book != null ? Cover(book) : (audio != null ? AudioCover(audio, shadow: false) : PodcastArt(show?.imageUrl ?? station?.favicon, title: title)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(t.zen ? 3 : 0),
                child: Stack(children: [
                  Container(height: 6, color: t.line),
                  FractionallySizedBox(widthFactor: seconds / max, child: Container(height: 6, color: t.accent)),
                ]),
              ),
              const SizedBox(height: 6),
              Label(detail, size: 9),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Ring extends CustomPainter {
  _Ring(this.value, this.t);
  final double value;
  final Tokens t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 6;
    if (t.zen) {
      final track = Paint()
        ..color = t.raised
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round;
      final rect = Rect.fromCircle(center: c, radius: r - 2);
      canvas.drawArc(rect, 0, math.pi * 2, false, track);
      if (value > 0) canvas.drawArc(rect, -math.pi / 2, value.clamp(0, 1) * math.pi * 2, false, track..color = t.accent);
      return;
    }
    // tick marks
    final tick = Paint()
      ..color = t.line
      ..strokeWidth = 2;
    final on = Paint()
      ..color = t.accent
      ..strokeWidth = 2.6;
    const n = 48;
    for (var i = 0; i < n; i++) {
      final a = -math.pi / 2 + i / n * math.pi * 2;
      final p1 = c + Offset(math.cos(a), math.sin(a)) * r;
      final p2 = c + Offset(math.cos(a), math.sin(a)) * (r - 9);
      canvas.drawLine(p1, p2, i < (value.clamp(0, 1) * n).round() ? on : tick);
    }
  }

  @override
  bool shouldRepaint(_Ring o) => o.value != value;
}

class _Bars extends StatelessWidget {
  const _Bars({required this.values, required this.labels, required this.goal});
  final List<double> values;
  final List<String> labels;
  final double goal;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final maxV = math.max(goal, values.fold(0.0, math.max));
    return LayoutBuilder(builder: (context, c) {
      final h = c.maxHeight - 18;
      return Stack(children: [
        Positioned(
          left: 0,
          right: 0,
          top: h - goal / maxV * h,
          child: Row(children: [
            Expanded(child: Container(height: 1, color: t.accent.withValues(alpha: .6))),
            const SizedBox(width: 4),
            Label('goal', size: 8, color: t.accent),
          ]),
        ),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (var i = 0; i < values.length; i++)
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                if (values[i] > 0) Label('${values[i].round()}', size: 7.5),
                const SizedBox(height: 2),
                Container(
                  height: math.max(2, values[i] / maxV * (h - 12)),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: i == values.length - 1 ? t.accent : (values[i] >= goal ? t.ink : t.muted.withValues(alpha: t.zen ? .3 : .6)),
                    borderRadius: t.zen ? BorderRadius.circular(3) : null,
                  ),
                ),
                const SizedBox(height: 4),
                Label(labels[i], size: 8.5, color: i == values.length - 1 ? t.ink : t.muted),
              ]),
            ),
        ]),
      ]);
    });
  }
}
