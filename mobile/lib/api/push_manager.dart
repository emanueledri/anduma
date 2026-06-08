// Gestione push (M7): init Firebase, permessi, registrazione device col token
// FCM, deep-link al tap della notifica, banner per i messaggi in foreground.
//
// Tutto è best-effort e degrada con grazia: se Firebase non è configurato
// (manca google-services.json) o i permessi sono negati, l'app continua a
// funzionare senza push — `available` resta false e nessuna funzione lancia.
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';

/// Destinazione di navigazione derivata dal payload `data` di una push.
class AppDeepLink {
  final String kind; // 'imminent' | 'strike'
  final String? stopId;
  final String? line;
  const AppDeepLink({required this.kind, this.stopId, this.line});

  factory AppDeepLink.fromData(Map<String, dynamic> data) => AppDeepLink(
        kind: (data['kind'] as String?) ?? '',
        stopId: data['stop_id'] as String?,
        line: data['line'] as String?,
      );
}

/// Handler dei messaggi in background/terminato. Il backend invia un payload
/// `notification`, quindi il sistema mostra la notifica da solo: qui non serve
/// fare nulla, ma l'handler va registrato (requisito di firebase_messaging).
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {}

class PushManager {
  PushManager(this._api);

  final ApiClient _api;
  static const _deviceIdKey = 'tt_device_id_v1';

  /// True se Firebase si è inizializzato e le notifiche sono utilizzabili.
  bool available = false;

  /// Deep-link in attesa di essere consumato dalla UI (tap su notifica).
  final ValueNotifier<AppDeepLink?> deepLink = ValueNotifier(null);

  /// Ultimo messaggio ricevuto in foreground (per un banner in-app).
  final ValueNotifier<RemoteMessage?> foreground = ValueNotifier(null);

  /// Inizializza Firebase + FCM. Idempotente, non lancia mai.
  Future<void> init() async {
    // 1) Carica un eventuale device id già registrato (header pronto subito).
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getInt(_deviceIdKey);
    if (saved != null) _api.deviceId = saved;

    // 2) Firebase: se non configurato, si resta senza push.
    try {
      await Firebase.initializeApp();
      available = true;
    } catch (e) {
      debugPrint('Push disabilitate (Firebase non configurato): $e');
      return;
    }

    final fm = FirebaseMessaging.instance;
    FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);

    // 3) Permesso notifiche (Android 13+ / iOS).
    await fm.requestPermission();

    // 4) Token → registrazione device (idempotente lato backend).
    try {
      final token = await fm.getToken();
      if (token != null) await _register(token);
    } catch (e) {
      debugPrint('Registrazione device fallita: $e');
    }
    fm.onTokenRefresh.listen((t) => _register(t).catchError((_) {}));

    // 5) Routing dei messaggi.
    FirebaseMessaging.onMessage.listen((m) => foreground.value = m);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleOpened);
    final initial = await fm.getInitialMessage();
    if (initial != null) _handleOpened(initial);
  }

  Future<void> _register(String token) async {
    final id = await _api.registerDevice(token: token);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_deviceIdKey, id);
  }

  void _handleOpened(RemoteMessage message) {
    if (message.data.isEmpty) return;
    deepLink.value = AppDeepLink.fromData(message.data);
  }

  /// Consuma il deep-link corrente (la UI lo azzera dopo aver navigato).
  void clearDeepLink() => deepLink.value = null;

  void dispose() {
    deepLink.dispose();
    foreground.dispose();
  }
}
