// Store osservabile delle sottoscrizioni alert dell'utente (M7).
// Sincronizzato col backend /me/subscriptions; richiede un device registrato
// (ApiClient.deviceId valorizzato dal PushManager). Se il device non è pronto
// le operazioni sono no-op silenziose: la UI mostra che le push non sono attive.
import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'models.dart';

class SubscriptionsStore extends ChangeNotifier {
  SubscriptionsStore(this._api);
  final ApiClient _api;

  List<Subscription> _subs = const [];
  bool _loaded = false;

  List<Subscription> get all => List.unmodifiable(_subs);
  bool get ready => _api.deviceId != null;
  bool get loaded => _loaded;

  /// Sottoscrizioni "imminent" attive per una fermata.
  List<Subscription> imminentForStop(String stopId) =>
      _subs.where((s) => s.kind == 'imminent' && s.stopId == stopId).toList();

  bool hasImminent(String stopId, String line) =>
      _subs.any((s) => s.kind == 'imminent' && s.stopId == stopId && s.line == line);

  Subscription? strikeForLine(String line) {
    for (final s in _subs) {
      if (s.kind == 'strike' && s.line == line) return s;
    }
    return null;
  }

  /// Conta gli alert che toccano una fermata (per il badge sulla card).
  int countForStop(String stopId) => imminentForStop(stopId).length;

  Future<void> load() async {
    if (!ready) return;
    try {
      _subs = await _api.subscriptions();
      _loaded = true;
      notifyListeners();
    } catch (_) {
      // device non pronto / offline: si riprova al prossimo trigger
    }
  }

  Future<bool> addImminent(String stopId, String line, int thresholdMin) async {
    if (!ready) return false;
    try {
      final sub = await _api.addImminentAlert(
          stopId: stopId, line: line, thresholdMin: thresholdMin);
      _subs = [..._subs, sub];
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> toggleStrike(String line, {required bool on}) async {
    if (!ready) return false;
    try {
      if (on) {
        final sub = await _api.addStrikeAlert(line: line);
        _subs = [..._subs, sub];
      } else {
        final existing = strikeForLine(line);
        if (existing != null) {
          await _api.deleteSubscription(existing.id);
          _subs = _subs.where((s) => s.id != existing.id).toList();
        }
      }
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> remove(int id) async {
    if (!ready) return false;
    try {
      await _api.deleteSubscription(id);
      _subs = _subs.where((s) => s.id != id).toList();
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }
}
