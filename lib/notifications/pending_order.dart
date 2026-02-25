import 'package:flutter/foundation.dart';

/// A tiny, Flutter-only bridge between `main.dart` (notifications/taps)
/// and `PorterHome` (order UI).
///
/// Why:
/// - Flutter cannot show UI while the app is background/terminated.
/// - Driver apps show a heads-up/full-screen notification in background, and
///   when the driver taps it (or the app returns to foreground) the in-app
///   order popup is shown immediately.
///
/// We keep it in-memory (no native code / no new MethodChannels).
class PendingOrder {
  static final ValueNotifier<String?> orderId = ValueNotifier<String?>(null);

  static void set(String? id) {
    final v = id?.trim();
    if (v == null || v.isEmpty) return;
    orderId.value = v;
  }

  static void clear() {
    orderId.value = null;
  }
}


