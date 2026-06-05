// Client REST verso il backend Transito Torino.
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'config.dart';
import 'models.dart';

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({http.Client? client, String? base})
      : _client = client ?? http.Client(),
        _base = base ?? ApiConfig.apiBase;

  final http.Client _client;
  final String _base;

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final q = (query ?? {})..removeWhere((_, v) => v == null);
    return Uri.parse('$_base$path').replace(
      queryParameters: q.isEmpty ? null : q.map((k, v) => MapEntry(k, '$v')),
    );
  }

  Future<dynamic> _get(String path, [Map<String, dynamic>? query]) async {
    final http.Response res;
    try {
      res = await _client.get(_uri(path, query)).timeout(const Duration(seconds: 12));
    } catch (e) {
      throw ApiException('Rete non raggiungibile');
    }
    if (res.statusCode == 404) throw ApiException('Non trovato');
    if (res.statusCode >= 400) throw ApiException('Errore server (${res.statusCode})');
    return jsonDecode(utf8.decode(res.bodyBytes));
  }

  Future<List<TransitLine>> lines() async {
    final data = await _get('/lines') as List;
    return data.map((e) => TransitLine.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<Stop>> searchStops(String q, {int limit = 20}) async {
    if (q.trim().isEmpty) return const [];
    final data = await _get('/stops/search', {'q': q, 'limit': limit}) as List;
    return data.map((e) => Stop.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<ArrivalsResponse> arrivals(String stopId, {String? line}) async {
    final data = await _get('/stops/$stopId/arrivals', {'line': line}) as Map<String, dynamic>;
    return ArrivalsResponse.fromJson(data);
  }

  Future<VehiclesResponse> vehicles(String line) async {
    final data = await _get('/lines/$line/vehicles') as Map<String, dynamic>;
    return VehiclesResponse.fromJson(data);
  }

  Future<AlertsResponse> alerts({String? line}) async {
    final data = await _get('/alerts', {'line': line}) as Map<String, dynamic>;
    return AlertsResponse.fromJson(data);
  }

  void close() => _client.close();
}
