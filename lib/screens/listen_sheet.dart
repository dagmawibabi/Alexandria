import 'package:material_ui/material_ui.dart';
import 'package:omni_ai/omni_ai.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../core/settings.dart';
import '../core/search_box.dart';
import '../core/theme.dart';
import '../core/ui.dart';
import '../services/ai.dart';
import '../services/speech.dart';

/// Voice setup for read-aloud. With [play], ends in a "Start listening"
/// button and returns true when the reader should begin.
Future<bool> showListenSheet(BuildContext context, {bool play = true}) async {
  await Ai.ready;
  if (!context.mounted) return false;
  final go = await showSheet<bool>(context, builder: (ctx) => Padding(padding: const EdgeInsets.fromLTRB(20, 4, 20, 24), child: ListenPanel(play: play)));
  await Speech.stop(); // silence any preview still playing
  return go ?? false;
}

class ListenPanel extends StatefulWidget {
  const ListenPanel({super.key, this.play = false});
  final bool play;

  @override
  State<ListenPanel> createState() => _ListenPanelState();
}

class _ListenPanelState extends State<ListenPanel> {
  static const _info = {
    'device': ('Built into your phone · free · offline', ''),
    'addis': ('Amharic, Afaan Oromo & Tigrinya voices', 'https://platform.addisassistant.com'),
    'elevenlabs': ('Lifelike voices in 30+ languages', 'https://elevenlabs.io/app/settings/api-keys'),
  };

  /// Voice lists survive closing the sheet; they are slow to fetch.
  static final Map<String, Future<List<Voice>>> _voices = {};

  final _key = TextEditingController();
  final _search = TextEditingController();
  String? _status;
  String? _previewing;

  String get _engine => Settings.i.ttsEngine;

  Future<List<Voice>> _list(String engine) => _voices[engine] ??= Ai.omni.listVoices(engine).then((v) => v, onError: (Object e) {
        _voices.remove(engine);
        throw e;
      });

  @override
  void dispose() {
    _key.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _saveKey() async {
    final id = _engine;
    final key = _key.text.trim();
    if (key.isEmpty) return;
    setState(() => _status = 'Checking…');
    final problem = await Ai.omni.verifyKey(id, key: key);
    if (problem == null) {
      await Ai.omni.setApiKey(id, key);
      _key.clear();
      _voices.remove(id);
    }
    if (mounted) setState(() => _status = problem == null ? 'Connected' : 'Error: $problem');
  }

  String _sample(Voice v) {
    final lang = (v.language ?? '').split(RegExp('[-_]')).first.toLowerCase();
    return VoicePicker.samples[lang] ?? 'Hello. This is how I will sound reading your book.';
  }

  Future<void> _preview(Voice v) async {
    final was = _previewing;
    await Speech.stop();
    if (was == v.id) return setState(() => _previewing = null);
    setState(() => _previewing = v.id);
    try {
      if (v.provider == 'device') {
        await DeviceSpeech.instance.speak(_sample(v), voice: v.id.isEmpty ? null : v.id, rate: Speech.rate, pitch: Settings.i.ttsPitch);
      } else {
        final url = v.previewUrl ?? (v.provider == 'addis' ? await Ai.omni.addis.voicePreviewUrl(v.id) : null);
        if (url != null && url.isNotEmpty) {
          await AiAudio.instance.playUrl(url, toggle: false, wait: true);
        } else {
          final clip = await Ai.omni.generateSpeech(text: _sample(v), model: Speech.model(v.provider), voice: v.id.isEmpty ? null : v.id, language: v.language);
          if (_previewing == v.id) await AiAudio.instance.play(clip, wait: true, speed: Speech.rate);
        }
      }
    } catch (e) {
      if (mounted) toast(context, '$e');
    } finally {
      if (mounted && _previewing == v.id) setState(() => _previewing = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return ListenableBuilder(
      listenable: Settings.i,
      builder: (context, _) {
        final s = Settings.i;
        final ready = Speech.configured(_engine);
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Label('Listen', color: t.accent),
          const SizedBox(height: 6),
          const Text('Who reads to you', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          for (final e in Speech.engines) _engineRow(context, e),
          if (_engine != 'device') ...[
            const SizedBox(height: 4),
            _keyPanel(context),
          ],
          if (_engine == 'elevenlabs' && ready) ...[
            const SizedBox(height: 12),
            const Label('Model'),
            const SizedBox(height: 8),
            Segmented<String>(
              values: const ['eleven_flash_v2_5', 'eleven_multilingual_v2', 'eleven_v3'],
              labels: const ['Flash', 'Multilingual', 'v3'],
              value: s.elevenModel,
              onChanged: (v) => s.elevenModel = v,
            ),
          ],
          if (ready) ...[
            const SizedBox(height: 16),
            _voicePicker(context),
          ],
          const SizedBox(height: 10),
          SliderRow(label: 'Speed', value: s.ttsRate, min: .2, max: 1, format: (v) => '${(v * 2).toStringAsFixed(2)}×', onChanged: (v) => s.ttsRate = v),
          if (Speech.engine == 'device')
            SliderRow(label: 'Pitch', value: s.ttsPitch, min: .5, max: 2, format: (v) => v.toStringAsFixed(2), onChanged: (v) => s.ttsPitch = v),
          if (widget.play) ...[
            const SizedBox(height: 14),
            PrimaryButton(
              ready ? 'Start listening' : 'Start with device voice',
              icon: Icons.play_arrow_sharp,
              expand: true,
              onTap: () => Navigator.pop(context, true),
            ),
          ],
        ]);
      },
    );
  }

  Widget _engineRow(BuildContext context, String e) {
    final t = Tokens.of(context);
    final on = _engine == e;
    return GestureDetector(
      onTap: () {
        haptic();
        Speech.stop();
        setState(() {
          _status = null;
          _previewing = null;
          _search.clear();
        });
        Settings.i.ttsEngine = e;
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(color: on ? t.ink : t.raised, borderRadius: t.br, border: t.zen ? null : Border.all(color: on ? t.ink : t.line)),
        child: Row(children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: Speech.configured(e) ? const Color(0xFF00C27A) : (on ? t.bg.withValues(alpha: .4) : t.line)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(Speech.name(e), style: TextStyle(color: on ? t.bg : t.ink, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(_info[e]!.$1, style: TextStyle(color: on ? t.bg.withValues(alpha: .7) : t.muted, fontSize: 12.5)),
            ]),
          ),
          if (e == 'device') Label('Default', color: on ? t.bg.withValues(alpha: .7) : t.muted, size: 9),
          if (e != 'device' && !Speech.configured(e)) Label('Needs key', color: on ? t.bg.withValues(alpha: .7) : t.muted, size: 9),
        ]),
      ),
    );
  }

  Widget _keyPanel(BuildContext context) {
    final t = Tokens.of(context);
    final id = _engine;
    final has = Speech.configured(id);
    return Panel(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Label('${Speech.name(id)} key', color: t.ink, weight: FontWeight.w600)),
          GestureDetector(onTap: () => launchUrlString(_info[id]!.$2, mode: LaunchMode.externalApplication), child: Label('Get key ↗', color: t.accent)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _key,
              obscureText: true,
              decoration: InputDecoration(hintText: has ? '•••••••• saved — paste to replace' : 'Paste API key'),
              onSubmitted: (_) => _saveKey(),
            ),
          ),
          const SizedBox(width: 8),
          ToolButton(Icons.check_sharp, active: true, onTap: _saveKey),
          if (has) ...[
            const SizedBox(width: 8),
            ToolButton(Icons.close_sharp, tooltip: 'Remove key', onTap: () async {
              await Ai.omni.setApiKey(id, null);
              _voices.remove(id);
              setState(() => _status = 'Removed');
            }),
          ],
        ]),
        if (_status != null) Padding(padding: const EdgeInsets.only(top: 8), child: Label(_status!, color: _status == 'Connected' ? const Color(0xFF00A86B) : t.muted)),
        if (!has) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Until a key is added, the device voice reads instead.', style: TextStyle(color: t.muted, fontSize: 12.5))),
      ]),
    );
  }

  Widget _voicePicker(BuildContext context) {
    final t = Tokens.of(context);
    final engine = _engine;
    final chosen = Settings.i.ttsVoice(engine);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Label('Voice'),
        const Spacer(),
        Flexible(child: Label(chosen.name.isEmpty ? 'Default' : chosen.name, color: t.ink)),
      ]),
      const SizedBox(height: 8),
      SearchBox(historyKey: 'voices', 
        controller: _search,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(hintText: 'Search by name, language, accent…', prefixIcon: Icon(Icons.search_sharp, size: 18)),
      ),
      const SizedBox(height: 8),
      Container(
        height: 290,
        decoration: BoxDecoration(color: t.bg, borderRadius: t.br, border: t.hair),
        child: FutureBuilder<List<Voice>>(
          future: _list(engine),
          builder: (context, snap) {
            if (snap.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('${snap.error}', textAlign: TextAlign.center, style: TextStyle(color: t.muted, fontSize: 12.5)),
                    const SizedBox(height: 10),
                    ToolButton(Icons.refresh_sharp, label: 'Retry', size: 34, onTap: () => setState(() => _voices.remove(engine))),
                  ]),
                ),
              );
            }
            if (!snap.hasData) return const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 1.5)));
            final q = _search.text.toLowerCase();
            final voices = [
              if (q.isEmpty) Voice(id: '', name: 'Default', provider: engine, description: engine == 'device' ? 'Your phone\'s chosen voice' : 'The provider\'s standard voice'),
              ...snap.data!.where((v) => q.isEmpty || '${v.name} ${v.traits} ${v.language ?? ''}'.toLowerCase().contains(q)),
            ];
            if (voices.isEmpty) return const Center(child: Label('No voices match'));
            return ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: voices.length,
              itemBuilder: (context, i) {
                final v = voices[i];
                final on = v.id == chosen.id;
                final playing = _previewing == v.id;
                final sub = [v.traits, if (v.traits.isEmpty) v.description ?? ''].where((x) => x.isNotEmpty).join(' · ');
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    haptic();
                    Settings.i.setTtsVoice(engine, id: v.id, name: v.id.isEmpty ? '' : v.name, lang: v.language ?? '');
                  },
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                    decoration: BoxDecoration(border: Border(left: BorderSide(color: on ? t.accent : Colors.transparent, width: 3))),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(v.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.ink, fontWeight: on ? FontWeight.w700 : FontWeight.w500)),
                          if (sub.isNotEmpty) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.muted, fontSize: 12)),
                        ]),
                      ),
                      IconButton(
                        tooltip: playing ? 'Stop' : 'Preview',
                        onPressed: () => _preview(v),
                        icon: Icon(playing ? Icons.stop_sharp : Icons.play_arrow_sharp, color: playing ? t.accent : t.ink),
                      ),
                    ]),
                  ),
                );
              },
            );
          },
        ),
      ),
    ]);
  }
}
