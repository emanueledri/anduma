// Configurazione client API. Override a build-time con:
//   flutter run --dart-define=TT_API_BASE=http://10.0.2.2:8000   (emulatore Android)
class ApiConfig {
  /// Base URL REST del backend. Default: localhost (web/desktop dev).
  static const apiBase = String.fromEnvironment(
    'TT_API_BASE',
    defaultValue: 'http://127.0.0.1:8000',
  );

  /// Base URL WebSocket, derivata da [apiBase] (http→ws, https→wss).
  static String get wsBase =>
      apiBase.replaceFirst(RegExp(r'^http'), 'ws');
}
