// Push notifications through Firebase Cloud Messaging (docs/CONCEPT.md, "Push").
//
// The Firebase project belongs to the app, not to the server it is signed in to, so its
// public identifiers come in at build time (--dart-define BORTLE_FCM_*, from the allskyhub
// hub's builds). A build without them has no push and is otherwise the same app. The token
// goes to the signed-in server (PUT /api/app/push-token), which sends only while this
// device stays signed in there.

import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'api/bortle_client.dart';
import 'l10n.dart';

const _projectId = String.fromEnvironment('BORTLE_FCM_PROJECT_ID');
const _senderId = String.fromEnvironment('BORTLE_FCM_SENDER_ID');
const _androidAppId = String.fromEnvironment('BORTLE_FCM_ANDROID_APP_ID');
const _androidApiKey = String.fromEnvironment('BORTLE_FCM_ANDROID_API_KEY');
const _iosAppId = String.fromEnvironment('BORTLE_FCM_IOS_APP_ID');
const _iosApiKey = String.fromEnvironment('BORTLE_FCM_IOS_API_KEY');

/// A notification the person tapped, or one that arrived while the app was open.
class PushTap {
  const PushTap({required this.path, this.server, this.title, this.body, this.opened = true});

  factory PushTap.fromMessage(RemoteMessage m, {required bool opened}) => PushTap(
    path: m.data['path'] as String? ?? '/',
    server: m.data['server'] as String?,
    title: m.notification?.title,
    body: m.notification?.body,
    opened: opened,
  );

  final String path;
  final String? server;
  final String? title;
  final String? body;

  /// True when the person tapped it; false when it came in with the app in front.
  final bool opened;
}

abstract class PushService {
  /// Registers this phone with [client]'s server; asks for permission when [ask]. False
  /// when push is not possible (a build without Firebase, no permission, offline).
  Future<bool> register(BortleClient client, {bool ask = true});

  /// Before signing out: the server stops pushing to this device.
  Future<void> unregister(BortleClient client);

  /// Taps on notifications and messages that arrive while the app is open.
  Stream<PushTap> get taps;
}

class FirebasePush implements PushService {
  final _taps = StreamController<PushTap>.broadcast();
  StreamSubscription<String>? _refresh;
  bool _listening = false;

  static bool get configured {
    final android = Platform.isAndroid;
    return _projectId.isNotEmpty &&
        _senderId.isNotEmpty &&
        (android
            ? _androidAppId.isNotEmpty && _androidApiKey.isNotEmpty
            : _iosAppId.isNotEmpty && _iosApiKey.isNotEmpty);
  }

  Future<FirebaseMessaging?> _messaging() async {
    if (!configured) return null;
    final android = Platform.isAndroid;
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: FirebaseOptions(
          apiKey: android ? _androidApiKey : _iosApiKey,
          appId: android ? _androidAppId : _iosAppId,
          messagingSenderId: _senderId,
          projectId: _projectId,
          iosBundleId: android ? null : 'eu.bortle.app',
        ),
      );
    }
    final messaging = FirebaseMessaging.instance;
    if (!_listening) {
      _listening = true;
      FirebaseMessaging.onMessage.listen((m) => _taps.add(PushTap.fromMessage(m, opened: false)));
      FirebaseMessaging.onMessageOpenedApp.listen((m) => _taps.add(PushTap.fromMessage(m, opened: true)));
      final first = await messaging.getInitialMessage();
      if (first != null) {
        // The app was started by this tap: hand it over once the shell listens.
        Timer.run(() => _taps.add(PushTap.fromMessage(first, opened: true)));
      }
    }
    return messaging;
  }

  @override
  Future<bool> register(BortleClient client, {bool ask = true}) async {
    try {
      final messaging = await _messaging();
      if (messaging == null) return false;
      var settings = await messaging.getNotificationSettings();
      if (settings.authorizationStatus == AuthorizationStatus.notDetermined) {
        if (!ask) return false;
        settings = await messaging.requestPermission();
      }
      if (settings.authorizationStatus == AuthorizationStatus.denied) return false;
      // The registration token FCM HTTP v1 addresses, as allskyhub's app does.
      // ignore: deprecated_member_use
      final token = await messaging.getToken();
      if (token == null) return false;
      final platform = Platform.isAndroid ? 'android' : 'ios';
      final lang = appEnglish ? 'en' : 'de';
      await client.registerPush(token, platform, lang);
      await _refresh?.cancel();
      // ignore: deprecated_member_use
      _refresh = messaging.onTokenRefresh.listen(
        (fresh) => client.registerPush(fresh, platform, lang).catchError((Object _) {}),
      );
      return true;
    } on Exception {
      return false;
    }
  }

  @override
  Future<void> unregister(BortleClient client) async {
    await _refresh?.cancel();
    _refresh = null;
    if (!configured) return;
    try {
      await client.unregisterPush();
    } on Exception {
      // Offline: signing the device out stops its pushes on the server anyway.
    }
  }

  @override
  Stream<PushTap> get taps => _taps.stream;
}

/// For tests and builds without push.
class NoPush implements PushService {
  final controller = StreamController<PushTap>.broadcast();
  int registered = 0;
  int unregistered = 0;

  @override
  Future<bool> register(BortleClient client, {bool ask = true}) async {
    registered++;
    return false;
  }

  @override
  Future<void> unregister(BortleClient client) async => unregistered++;

  @override
  Stream<PushTap> get taps => controller.stream;
}

/// The app's push service; tests put [NoPush] here.
PushService pushService = FirebasePush();
