import 'package:omni_ai/omni_ai.dart';

import '../core/settings.dart';
import 'ai.dart';
import 'usage_log.dart';

/// Read-aloud for the whole app: the device voice, Addis AI or ElevenLabs.
///
/// Everything goes through omni_ai's [DeviceSpeech] and [AiAudio] so only one
/// text-to-speech engine is ever alive (a second `FlutterTts` would steal the
/// first one's completion callbacks).
class Speech {
  Speech._();

  static const engines = ['device', 'addis', 'elevenlabs'];

  static OmniAI get _ai => Ai.omni;

  static String name(String engine) => switch (engine) {
        'addis' => 'Addis AI',
        'elevenlabs' => 'ElevenLabs',
        _ => 'Device voice',
      };

  static bool configured(String engine) => switch (engine) {
        'addis' => _ai.addis.isConfigured,
        'elevenlabs' => _ai.elevenLabs.isConfigured,
        _ => true,
      };

  /// The engine in use: the chosen one if it has a key, otherwise the device.
  static String get engine {
    final e = Settings.i.ttsEngine;
    return configured(e) ? e : 'device';
  }

  /// "ElevenLabs · Rachel"
  static String get summary {
    final e = engine;
    final v = Settings.i.ttsVoice(e);
    return '${name(e)} · ${v.name.isEmpty ? 'default' : v.name}';
  }

  /// The speech model id omni_ai should use for a cloud [engine].
  static String model(String engine) =>
      engine == 'addis' ? 'addis:${_ai.addis.defaultModels[ModelType.speech]}' : 'elevenlabs:${Settings.i.elevenModel}';

  /// The reader's rate slider treats 0.5 as normal speed.
  static double get rate => (Settings.i.ttsRate * 2).clamp(.4, 2.0);

  /// The last cloud failure, so the reader can say why it fell back to the device voice.
  static Object? lastError;

  static int _gen = 0;
  static final Map<String, Future<GeneratedFile>> _clips = {};

  static List<String> _parts(String text, {int size = 900}) => DeviceSpeech.chunk(DeviceSpeech.clean(text), size: size);

  /// [text] split for reading: short for the device voice, so pausing loses little;
  /// longer for cloud voices, which charge and start per clip.
  static List<String> partsOf(String text) => _parts(text, size: engine == 'device' ? 380 : 900);

  static Future<GeneratedFile> _clip(String engine, String text) {
    final v = Settings.i.ttsVoice(engine);
    final key = '$engine|${v.id}|${Settings.i.elevenModel}|$text';
    final hit = _clips[key];
    if (hit != null) return hit;
    if (_clips.length > 12) _clips.remove(_clips.keys.first);
    UsageLog.i.addSpeechChars(engine, text.length);
    final f = _ai.generateSpeech(text: text, model: model(engine), voice: v.id.isEmpty ? null : v.id, language: v.lang.isEmpty ? null : v.lang);
    f.then((_) {}, onError: (_) {
      _clips.remove(key);
    });
    return _clips[key] = f;
  }

  /// Starts generating [text] with a cloud voice so it is ready when [say] gets to it.
  static void prepare(String text) {
    final e = engine;
    if (e == 'device') return;
    final parts = _parts(text);
    if (parts.isNotEmpty) _clip(e, parts.first).ignore();
  }

  /// Reads [text] aloud; completes when it is done or [stop] is called.
  /// A cloud voice that fails hands over to the device voice where it left off.
  static Future<void> say(String text) async {
    final gen = _gen;
    final e = engine;
    var parts = _parts(text);
    if (parts.isEmpty) return;
    if (e != 'device') {
      var i = 0;
      try {
        for (; i < parts.length; i++) {
          final clip = await _clip(e, parts[i]);
          if (gen != _gen) return;
          if (i + 1 < parts.length) _clip(e, parts[i + 1]).ignore();
          final started = DateTime.now();
          await AiAudio.instance.play(clip, wait: true, speed: rate);
          // Addis bills by audio length; sped-up playback is still that much audio.
          UsageLog.i.addSpeechSeconds(e, DateTime.now().difference(started).inMilliseconds / 1000 * rate);
          if (gen != _gen) return;
        }
        return;
      } catch (err) {
        lastError = err;
        if (gen != _gen) return;
        parts = parts.sublist(i);
      }
    }
    final v = Settings.i.ttsVoice('device');
    for (final part in parts) {
      await DeviceSpeech.instance.speak(part, voice: v.id.isEmpty ? null : v.id, rate: rate, pitch: Settings.i.ttsPitch);
      if (gen != _gen) return;
    }
  }

  static Future<void> stop() async {
    _gen++;
    await AiAudio.instance.stop();
    await DeviceSpeech.instance.stop();
  }
}
