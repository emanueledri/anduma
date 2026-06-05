// Streaming posizioni mezzi via WebSocket (WS /ws/lines/{line}), con fallback.
import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'api_client.dart';
import 'config.dart';
import 'models.dart';

/// Stato della connessione realtime mostrato in UI (badge mappa).
enum RealtimeStatus { connecting, live, paused }

class VehiclesUpdate {
  final VehiclesResponse data;
  final RealtimeStatus status;
  const VehiclesUpdate(this.data, this.status);
}

/// Sottoscrive il WS della linea e ne emette gli aggiornamenti. Se il WS cade,
/// passa a `paused` e fa **fallback** al polling REST di `/lines/{line}/vehicles`
/// (stesso payload), come documentato nel backend (M5).
class VehiclesStream {
  VehiclesStream(this.line, {ApiClient? api}) : _api = api ?? ApiClient();

  final String line;
  final ApiClient _api;
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _pollTimer;
  final _controller = StreamController<VehiclesUpdate>.broadcast();

  Stream<VehiclesUpdate> get stream => _controller.stream;

  void start() {
    _connectWs();
  }

  void _connectWs() {
    try {
      final uri = Uri.parse('${ApiConfig.wsBase}/ws/lines/$line');
      _channel = WebSocketChannel.connect(uri);
      _sub = _channel!.stream.listen(
        (event) {
          try {
            final json = jsonDecode(event as String) as Map<String, dynamic>;
            _controller.add(VehiclesUpdate(VehiclesResponse.fromJson(json), RealtimeStatus.live));
          } catch (_) {/* frame malformato: ignora */}
        },
        onError: (_) => _fallbackToPolling(),
        onDone: _fallbackToPolling,
        cancelOnError: true,
      );
    } catch (_) {
      _fallbackToPolling();
    }
  }

  // Fallback: polling REST ogni 4s, segnalando lo stato come "in pausa" (non live).
  void _fallbackToPolling() {
    if (_pollTimer != null) return;
    _poll();
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) => _poll());
  }

  Future<void> _poll() async {
    try {
      final data = await _api.vehicles(line);
      if (!_controller.isClosed) {
        _controller.add(VehiclesUpdate(data, RealtimeStatus.paused));
      }
    } catch (_) {/* offline: mantieni l'ultimo stato noto */}
  }

  Future<void> dispose() async {
    _pollTimer?.cancel();
    await _sub?.cancel();
    await _channel?.sink.close();
    await _controller.close();
    _api.close();
  }
}
