// Preferiti locali — persistiti in SharedPreferences (nessun backend in M6).
// La sincronizzazione col backend /me/favorites avverrà in M7 con il device token FCM.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalFavorite {
  final String type; // 'stop' | 'line'
  final String ref; // stop_id oppure numero linea
  final String name; // nome visualizzato (nome fermata o "Linea X")

  const LocalFavorite({required this.type, required this.ref, required this.name});

  Map<String, dynamic> toJson() => {'type': type, 'ref': ref, 'name': name};

  factory LocalFavorite.fromJson(Map<String, dynamic> j) => LocalFavorite(
        type: j['type'] as String,
        ref: j['ref'] as String,
        name: (j['name'] as String?) ?? (j['ref'] as String),
      );

  @override
  bool operator ==(Object other) =>
      other is LocalFavorite && other.type == type && other.ref == ref;

  @override
  int get hashCode => Object.hash(type, ref);
}

/// Store osservabile dei preferiti. Usare [ListenableBuilder] per reagire ai
/// cambiamenti. Caricare con [load] all'avvio (una sola volta).
class FavoritesStore extends ChangeNotifier {
  static const _prefKey = 'tt_favorites_v1';
  List<LocalFavorite> _favs = [];

  List<LocalFavorite> get favorites => List.unmodifiable(_favs);
  List<LocalFavorite> get stops =>
      _favs.where((f) => f.type == 'stop').toList();
  List<LocalFavorite> get lines =>
      _favs.where((f) => f.type == 'line').toList();

  bool has(String type, String ref) =>
      _favs.any((f) => f.type == type && f.ref == ref);

  /// Carica da SharedPreferences. Chiamare una sola volta in [initState].
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKey);
    if (raw == null) return;
    try {
      final list = jsonDecode(raw) as List;
      _favs =
          list.map((e) => LocalFavorite.fromJson(e as Map<String, dynamic>)).toList();
      notifyListeners();
    } catch (_) {
      // prefs corrotte: si ignorano senza crash
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _prefKey, jsonEncode(_favs.map((e) => e.toJson()).toList()));
  }

  Future<void> add(LocalFavorite fav) async {
    if (has(fav.type, fav.ref)) return;
    _favs = [..._favs, fav];
    notifyListeners();
    await _persist();
  }

  Future<void> remove(String type, String ref) async {
    _favs = _favs.where((f) => !(f.type == type && f.ref == ref)).toList();
    notifyListeners();
    await _persist();
  }
}
