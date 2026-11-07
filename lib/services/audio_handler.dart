import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'audio.dart';
import 'read_aloud.dart';

/// Mirrors [Player] into the system media session: the notification,
/// lock screen, Bluetooth buttons and headset controls.
class AlexandriaAudioHandler extends BaseAudioHandler with SeekHandler {
  AlexandriaAudioHandler() {
    Player.i.addListener(_sync);
    ReadAloud.i.addListener(_sync);
  }

  /// Starts the media session. Platforms without audio_service (desktop dev) just skip it.
  static Future<void> init() async {
    try {
      await AudioService.init(
        builder: AlexandriaAudioHandler.new,
        config: const AudioServiceConfig(
          // MainActivity creates this channel first, so it shows on the lock screen.
          androidNotificationChannelId: 'alexandria.player',
          androidNotificationChannelName: 'Now playing',
          androidNotificationChannelDescription: 'Audiobook and podcast controls',
          androidNotificationIcon: 'drawable/ic_launcher_monochrome',
          androidStopForegroundOnPause: true,
          fastForwardInterval: Duration(seconds: 30),
          rewindInterval: Duration(seconds: 10),
        ),
      );
    } catch (e) {
      debugPrint('[audio] media session unavailable: $e');
    }
  }

  String _itemKey = '';
  String _stateKey = '';
  bool _askedForNotifications = false;

  /// Android 13+ hides the playback notification (and with it the lock-screen
  /// controls) until notifications are allowed, so ask the first time anything plays.
  void _askForNotifications() {
    if (_askedForNotifications || !Platform.isAndroid) return;
    _askedForNotifications = true;
    const MethodChannel('alexandria/power').invokeMethod('askNotifications').catchError((_) => null).ignore();
  }

  void _sync() {
    if (Player.i.playing || ReadAloud.i.playing) _askForNotifications();
    if (ReadAloud.i.active) return _syncRead();
    final pl = Player.i;
    final b = pl.book;
    if (b == null) {
      if (_stateKey != 'idle') {
        _stateKey = 'idle';
        _itemKey = '';
        playbackState.add(PlaybackState(processingState: AudioProcessingState.idle, playing: false));
      }
      return;
    }
    final t = pl.current;
    final many = b.tracks.length > 1;

    final key = '${b.id}#${b.trackIndex}#${pl.duration.inSeconds}#${b.coverPath}';
    if (key != _itemKey) {
      _itemKey = key;
      final art = b.coverPath != null && File(b.coverPath!).existsSync() ? Uri.file(b.coverPath!) : (b.coverUrl == null ? null : Uri.tryParse(b.coverUrl!));
      mediaItem.add(MediaItem(
        id: key,
        title: b.title,
        artist: many ? (t?.title ?? b.author) : b.author,
        album: many ? b.author : null,
        duration: pl.duration > Duration.zero ? pl.duration : null,
        artUri: art,
      ));
    }

    // Position extrapolates on its own while playing; only push real changes,
    // plus a resync every 10 s of playback.
    final state = '${pl.playing}#${pl.loading}#${b.speed}#${b.trackIndex}#${pl.position.inSeconds ~/ 10}';
    if (state == _stateKey) return;
    _stateKey = state;
    if (b.source == 'radio') {
      playbackState.add(PlaybackState(
        controls: [pl.playing ? MediaControl.pause : MediaControl.play, MediaControl.stop],
        androidCompactActionIndices: const [0, 1],
        processingState: pl.loading ? AudioProcessingState.loading : AudioProcessingState.ready,
        playing: pl.playing,
        speed: 0,
      ));
      return;
    }
    playbackState.add(PlaybackState(
      controls: [
        MediaControl.rewind,
        pl.playing ? MediaControl.pause : MediaControl.play,
        MediaControl.fastForward,
        if (many && b.trackIndex < b.tracks.length - 1) MediaControl.skipToNext,
      ],
      systemActions: const {MediaAction.seek, MediaAction.seekForward, MediaAction.seekBackward, MediaAction.skipToPrevious},
      androidCompactActionIndices: const [0, 1, 2],
      processingState: pl.loading ? AudioProcessingState.loading : AudioProcessingState.ready,
      playing: pl.playing,
      updatePosition: pl.position,
      speed: b.speed,
    ));
  }

  /// A book being read aloud: previous and next move by paragraph.
  void _syncRead() {
    final r = ReadAloud.i;
    final b = r.book!;
    final total = r.length;
    final key = 'read:${b.id}#${r.chapter}#${b.coverPath}';
    if (key != _itemKey) {
      _itemKey = key;
      mediaItem.add(MediaItem(
        id: key,
        title: b.title,
        artist: r.chapter.isNotEmpty ? r.chapter : b.author,
        album: b.author,
        duration: total > Duration.zero ? total : null,
        artUri: b.coverPath != null && File(b.coverPath!).existsSync() ? Uri.file(b.coverPath!) : null,
      ));
    }
    final state = 'read#${r.playing}#${r.block}';
    if (state == _stateKey) return;
    _stateKey = state;
    playbackState.add(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        r.playing ? MediaControl.pause : MediaControl.play,
        MediaControl.skipToNext,
        MediaControl.stop,
      ],
      systemActions: const {MediaAction.seek},
      androidCompactActionIndices: const [0, 1, 2],
      processingState: AudioProcessingState.ready,
      playing: r.playing,
      updatePosition: total * r.fraction,
      // Position moves paragraph by paragraph, not by the clock.
      speed: 0,
    ));
  }

  @override
  Future<void> play() => ReadAloud.i.active ? ReadAloud.i.resume() : Player.i.resume();

  @override
  Future<void> pause() => ReadAloud.i.active ? ReadAloud.i.pause() : Player.i.pause();

  @override
  Future<void> seek(Duration position) {
    if (!ReadAloud.i.active) return Player.i.seek(position);
    final total = ReadAloud.i.length.inMilliseconds;
    return ReadAloud.i.seek(total == 0 ? 0 : position.inMilliseconds / total);
  }

  @override
  Future<void> fastForward() => ReadAloud.i.active ? ReadAloud.i.next() : Player.i.skip(30);

  @override
  Future<void> rewind() => ReadAloud.i.active ? ReadAloud.i.previous() : Player.i.skip(-10);

  @override
  Future<void> skipToNext() => ReadAloud.i.active ? ReadAloud.i.next() : Player.i.next();

  @override
  Future<void> skipToPrevious() => ReadAloud.i.active ? ReadAloud.i.previous() : Player.i.previous();

  @override
  Future<void> setSpeed(double speed) => ReadAloud.i.active ? Future.value() : Player.i.setSpeed(speed);

  @override
  Future<void> stop() async {
    if (ReadAloud.i.active) {
      await ReadAloud.i.stop();
    } else {
      await Player.i.close();
    }
    await super.stop();
  }
}
