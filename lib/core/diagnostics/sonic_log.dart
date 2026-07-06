import 'package:flutter/foundation.dart';

/// Lightweight tagged logging for the signaling/WebRTC flow.
///
/// Uses [debugPrint], which still emits in release builds (unlike `assert`),
/// so the output shows up in `adb logcat` as `I/flutter` lines prefixed with
/// `[SonicRelay/<tag>]`. Filter with: `adb logcat | grep SonicRelay`.
void sonicLog(String tag, String message) {
  debugPrint('[SonicRelay/$tag] $message');
}
