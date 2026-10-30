import 'package:material_ui/material_ui.dart';

import '../core/theme.dart';
import '../core/ui.dart';
import '../services/ai.dart';
import '../services/speech.dart';
import '../services/usage_log.dart';

String _count(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 10000) return '${(n / 1000).round()}k';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
  return '$n';
}

String _usd(double v) {
  if (v == 0) return '\$0';
  if (v < .01) return '<\$0.01';
  return '\$${v.toStringAsFixed(2)}';
}

/// Tokens and cost for the user's own API keys. Hidden until there's a key or some use.
class UsageSection extends StatefulWidget {
  const UsageSection({super.key});

  @override
  State<UsageSection> createState() => _UsageSectionState();
}

class _UsageSectionState extends State<UsageSection> {
  String _period = 'month';

  /// The ElevenLabs plan's quota, which is the only cost figure it can give.
  Future<Map<String, dynamic>>? _eleven;

  @override
  void initState() {
    super.initState();
    if (Ai.omni.elevenLabs.isConfigured) _eleven = Ai.omni.elevenLabs.subscription();
    // The list prices used for estimates.
    Ai.omni.catalog.load().catchError((_) {});
  }

  DateTime? get _from {
    final now = DateTime.now();
    return switch (_period) {
      'today' => now,
      'week' => now.subtract(const Duration(days: 6)),
      'month' => DateTime(now.year, now.month),
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return ListenableBuilder(
      listenable: UsageLog.i,
      builder: (context, _) {
        final log = UsageLog.i;
        final hasKey = Ai.configured || Speech.configured('addis') || Speech.configured('elevenlabs');
        if (!hasKey && log.rows.isEmpty) return const SizedBox.shrink();

        final rows = log.since(_from).toList();
        final total = UsageTotal();
        final perModel = <String, UsageTotal>{};
        var addisSecs = 0.0;
        var addisChars = 0, elevenChars = 0;
        for (final r in rows) {
          if (r.isSpeech) {
            if (r.model == 'speech:addis') {
              addisSecs += r.seconds;
              addisChars += r.chars;
            } else {
              elevenChars += r.chars;
            }
            continue;
          }
          total.add(r);
          (perModel[r.model] ??= UsageTotal()).add(r);
        }
        final models = perModel.entries.toList()..sort((a, b) => b.value.tokens.compareTo(a.value.tokens));
        final etb = addisSecs / 60 * UsageLog.addisEtbPerMinute;

        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionHeader('', 'AI tokens & cost', padding: EdgeInsets.fromLTRB(0, 28, 0, 12)),
          Segmented<String>(values: const ['today', 'week', 'month', 'all'], labels: const ['Today', '7 days', 'Month', 'All'], value: _period, onChanged: (v) => setState(() => _period = v)),
          const SizedBox(height: 10),
          Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: _Figure(_count(total.tokens), 'tokens')),
                Expanded(child: _Figure(_usd(total.usd), total.estimated > 0 ? 'estimated cost' : 'cost')),
                Expanded(child: _Figure('${total.calls}', 'AI requests')),
              ]),
              if (total.tokens > 0) ...[
                const SizedBox(height: 10),
                Text('${_count(total.input)} sent · ${_count(total.output)} received', style: TextStyle(color: t.muted, fontSize: 13)),
              ],
              for (final m in models.take(6)) ...[
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: Text(m.key.split(':').last, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5))),
                  const SizedBox(width: 8),
                  Text('${_count(m.value.tokens)} · ${m.value.unpriced > 0 && m.value.usd == 0 ? 'no price' : _usd(m.value.usd)}', style: TextStyle(color: t.muted, fontSize: 13)),
                ]),
              ],
              if (total.calls == 0) Text('Nothing in this period.', style: TextStyle(color: t.muted, fontSize: 13)),
            ]),
          ),
          if (Speech.configured('addis') || addisChars > 0) ...[
            const SizedBox(height: 10),
            _Voice(
              name: 'Addis AI voice',
              figures: [(_count(addisChars), 'characters'), ('${(addisSecs / 60).toStringAsFixed(1)} min', 'played'), ('~${etb.toStringAsFixed(1)} ETB', 'estimated')],
              note: 'At ${UsageLog.addisEtbPerMinute.toStringAsFixed(0)} ETB a minute. Estimated from audio you played, so voice previews and audio prepared but not heard aren\'t counted.',
            ),
          ],
          if (Speech.configured('elevenlabs') || elevenChars > 0) ...[
            const SizedBox(height: 10),
            FutureBuilder<Map<String, dynamic>>(
              future: _eleven,
              builder: (context, snap) {
                final used = snap.data?['character_count'];
                final limit = snap.data?['character_limit'];
                return _Voice(
                  name: 'ElevenLabs voice',
                  figures: [(_count(elevenChars), 'characters'), if (used is num && limit is num) ('${_count(used.toInt())} / ${_count(limit.toInt())}', 'plan this period')],
                  note: 'Charged from your plan\'s characters. The plan figure is your whole account, including use outside Alexandria.',
                );
              },
            ),
          ],
          const SizedBox(height: 8),
          Text(
            [
              'Reported by the provider where it can; otherwise estimated from list prices, so free tiers can show a cost you weren\'t actually charged. Check your provider for the real bill.',
              if (total.unpriced > 0) '${total.unpriced} requests had no known price and aren\'t in the cost.',
            ].join(' '),
            style: TextStyle(color: t.muted, fontSize: 12.5, height: 1.4),
          ),
          if (log.rows.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () async {
                  if (await confirm(context, 'Reset usage', 'Clears these token and cost figures on this device. Your provider\'s records aren\'t affected.')) log.clear();
                },
                child: Label('Reset usage', color: t.muted),
              ),
            ),
        ]);
      },
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure(this.value, this.label);
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: t.ink))),
      const SizedBox(height: 2),
      Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.muted, fontSize: 12)),
    ]);
  }
}

class _Voice extends StatelessWidget {
  const _Voice({required this.name, required this.figures, required this.note});
  final String name;
  final List<(String, String)> figures;
  final String note;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
        const SizedBox(height: 10),
        Row(children: [for (final f in figures) Expanded(child: _Figure(f.$1, f.$2))]),
        const SizedBox(height: 8),
        Text(note, style: TextStyle(color: t.muted, fontSize: 12.5, height: 1.4)),
      ]),
    );
  }
}
