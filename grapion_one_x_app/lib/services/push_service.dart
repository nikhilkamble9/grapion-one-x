// //Added By Nikhil 22Nov26 00:10 For push notifications (Firebase Cloud Messaging) — Android now, web/iOS later
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'api_client.dart';

/// Lets the app show a banner for pushes that arrive while it is open.
final GlobalKey<ScaffoldMessengerState> appMessengerKey = GlobalKey<ScaffoldMessengerState>();

class PushService {
  PushService._();

  static bool _ready = false;
  static String? _token; // last token Firebase gave this device

  /// Only Android has a Firebase config (android/app/google-services.json) so far.
  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> init() async {
    if (!supported || _ready) return;
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onMessage.listen((m) {
        final n = m.notification;
        if (n == null) return;
        appMessengerKey.currentState?.showSnackBar(
          SnackBar(content: Text([n.title, n.body].whereType<String>().join(' — '))),
        );
      });
      // onRegistered fires after register() and again whenever Firebase rotates the token.
      FirebaseMessaging.instance.onRegistered.listen((t) {
        _token = t;
        _upload(t);
      });
      _ready = true;
    } catch (e) {
      debugPrint('Push disabled: ${e.runtimeType}'); // app keeps working with the in-app bell
    }
  }

  /// Call after login: asks permission (Android 13+) and registers this device with our server.
  static Future<void> registerDevice() async {
    if (!_ready) return;
    try {
      final perm = await FirebaseMessaging.instance.requestPermission();
      if (perm.authorizationStatus == AuthorizationStatus.denied) return;
      await FirebaseMessaging.instance.register(); // token arrives on onRegistered
    } catch (e) {
      debugPrint('Push registration skipped: ${e.runtimeType}');
    }
  }

  /// Call on sign-out so this phone stops receiving the previous user's notifications.
  static Future<void> unregisterDevice() async {
    if (!_ready) return;
    try {
      final token = _token;
      if (token != null) await apiClient.post('/notifications/push-token/remove', {'token': token});
      await FirebaseMessaging.instance.unregister();
      _token = null;
    } catch (_) {}
  }

  static Future<void> _upload(String token) async {
    await apiClient.post('/notifications/push-token', {'token': token, 'platform': 'android'});
  }
}
