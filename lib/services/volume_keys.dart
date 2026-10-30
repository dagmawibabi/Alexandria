import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// The phone's volume buttons as page turners. Android only hands them over while
/// [capture] is on; the rest of the time they change the volume as usual.
class VolumeKeys {
  VolumeKeys._();

  static const _channel = MethodChannel('alexandria/volumekeys');

  /// Tells a reader when something opens on top of it, so a sheet or dialog
  /// doesn't leave the buttons turning pages behind it.
  static final routes = RouteObserver<ModalRoute<void>>();

  /// Called with +1 for volume down and -1 for volume up.
  static ValueChanged<int>? onTurn;

  static bool _captured = false;
  static bool _listening = false;

  /// Listening needs the buttons for the volume, whatever the setting says.
  static bool wanted({required bool enabled, required bool covered, required bool audioPlaying}) => enabled && !covered && !audioPlaying;

  static void capture(bool on) {
    if (on == _captured) return;
    _captured = on;
    if (!_listening) {
      _listening = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'turn') onTurn?.call(call.arguments as int);
      });
    }
    // Other platforms have no such channel, and the buttons simply stay as they are.
    _channel.invokeMethod('capture', on).catchError((_) {});
  }
}
