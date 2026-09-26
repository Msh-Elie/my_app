import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// URL par défaut du backend : instance Render, joignable depuis n'importe
/// quel réseau (Wi-Fi ou 4G), aucune config manuelle nécessaire.
/// Peut être surchargée à la compilation (--dart-define=BACKEND_BASE=...)
/// ou à chaud dans l'app (Paramètres → Serveur backend) pour du dev local.
const String kDefaultBackendBase = String.fromEnvironment(
  'BACKEND_BASE',
  defaultValue: 'https://switchmoney-backend.onrender.com',
);

class AppUser {
  final int id;
  final String phone;
  final String name;
  final String? email;

  const AppUser({
    required this.id,
    required this.phone,
    required this.name,
    this.email,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: (json['id'] as num?)?.toInt() ?? 0,
      phone: json['phone']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'phone': phone,
        'name': name,
        'email': email,
      };
}

class ApiException implements Exception {
  final String message;
  final int? statusCode;

  const ApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

/// Délai généreux pour tolérer le réveil à froid d'un backend hébergé sur
/// un plan gratuit (le service s'endort après inactivité et peut mettre
/// jusqu'à ~50s à répondre à la première requête suivante).
const Duration kColdStartTimeout = Duration(seconds: 55);

/// Client HTTP unique de l'application : gère l'URL du backend
/// (modifiable dans les paramètres), le jeton de session et
/// l'en-tête Authorization sur chaque appel.
class ApiClient {
  ApiClient._();

  static final ApiClient instance = ApiClient._();

  static const String _tokenKey = 'auth_token_v1';
  static const String _userKey = 'auth_user_v1';
  static const String _baseUrlKey = 'backend_base_url_v1';

  String _baseUrl = kDefaultBackendBase;
  String? _token;
  AppUser? _user;
  bool _initialized = false;

  String get baseUrl => _baseUrl;
  bool get isLoggedIn => _token != null && _token!.isNotEmpty;
  AppUser? get user => _user;

  /// Réinitialise l'état du singleton (utilisé entre deux tests).
  @visibleForTesting
  void resetForTests() {
    _initialized = false;
    _token = null;
    _user = null;
    _baseUrl = kDefaultBackendBase;
  }

  Future<void> init() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString(_baseUrlKey) ?? kDefaultBackendBase;
    _token = prefs.getString(_tokenKey);
    final rawUser = prefs.getString(_userKey);
    if (rawUser != null && rawUser.isNotEmpty) {
      try {
        _user = AppUser.fromJson(jsonDecode(rawUser) as Map<String, dynamic>);
      } catch (_) {
        _user = null;
      }
    }
    _initialized = true;
  }

  Future<void> setBaseUrl(String url) async {
    var normalized = url.trim().replaceAll(RegExp(r'/+$'), '');
    if (normalized.isEmpty) {
      normalized = kDefaultBackendBase;
    } else if (!normalized.startsWith('http://') &&
        !normalized.startsWith('https://')) {
      normalized = 'http://$normalized';
    }
    _baseUrl = normalized;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_baseUrlKey, normalized);
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_token != null && _token!.isNotEmpty)
          'Authorization': 'Bearer $_token',
      };

  Uri _uri(String path) => Uri.parse('$_baseUrl$path');

  Future<http.Response> postJson(
    String path,
    Map<String, dynamic> body, {
    Duration timeout = const Duration(seconds: 12),
  }) {
    return http
        .post(_uri(path), headers: _headers, body: jsonEncode(body))
        .timeout(timeout);
  }

  Future<http.Response> getJson(
    String path, {
    Duration timeout = const Duration(seconds: 10),
  }) {
    return http.get(_uri(path), headers: _headers).timeout(timeout);
  }

  Map<String, dynamic> _decode(http.Response response) {
    if (response.body.isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(response.body);
    return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
  }

  Future<void> _storeSession(String token, AppUser user) async {
    _token = token;
    _user = user;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_userKey, jsonEncode(user.toJson()));
  }

  // --- Authentification ---

  Future<AppUser> register({
    required String name,
    required String phone,
    required String pin,
    String? email,
  }) async {
    final http.Response response;
    try {
      response = await postJson(
        '/api/auth/register',
        {
          'name': name,
          'phone': phone,
          'pin': pin,
          if (email != null && email.isNotEmpty) 'email': email,
        },
        timeout: kColdStartTimeout,
      );
    } on TimeoutException {
      throw const ApiException(
          'Le serveur ne répond pas — s\'il vient de se réveiller après une pause, réessayez dans quelques secondes.');
    } catch (_) {
      throw const ApiException(
          'Serveur injoignable — vérifiez l\'URL du backend dans Paramètres.');
    }

    final data = _decode(response);
    if (response.statusCode == 201 && data['token'] != null) {
      final user = AppUser.fromJson(data['user'] as Map<String, dynamic>);
      await _storeSession(data['token'] as String, user);
      return user;
    }
    throw ApiException(
      data['message']?.toString() ?? 'Inscription impossible',
      statusCode: response.statusCode,
    );
  }

  Future<AppUser> login({required String phone, required String pin}) async {
    final http.Response response;
    try {
      response = await postJson(
        '/api/auth/login',
        {
          'phone': phone,
          'pin': pin,
        },
        timeout: kColdStartTimeout,
      );
    } on TimeoutException {
      throw const ApiException(
          'Le serveur ne répond pas — s\'il vient de se réveiller après une pause, réessayez dans quelques secondes.');
    } catch (_) {
      throw const ApiException(
          'Serveur injoignable — vérifiez l\'URL du backend dans Paramètres.');
    }

    final data = _decode(response);
    if (response.statusCode == 200 && data['token'] != null) {
      final user = AppUser.fromJson(data['user'] as Map<String, dynamic>);
      await _storeSession(data['token'] as String, user);
      return user;
    }
    throw ApiException(
      data['message']?.toString() ?? 'Connexion impossible',
      statusCode: response.statusCode,
    );
  }

  /// Rafraîchit le profil depuis le serveur ; renvoie null (sans déconnecter)
  /// si le serveur est injoignable, mais déconnecte si le jeton est refusé.
  Future<AppUser?> fetchMe() async {
    if (!isLoggedIn) return null;
    try {
      final response = await getJson('/api/auth/me', timeout: kColdStartTimeout);
      if (response.statusCode == 200) {
        final data = _decode(response);
        final user = AppUser.fromJson(data['user'] as Map<String, dynamic>);
        await _storeSession(_token!, user);
        return user;
      }
      if (response.statusCode == 401) {
        await logout();
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<AppUser> updateProfile({required String name, String? email}) async {
    final response = await http
        .put(
          _uri('/api/auth/profile'),
          headers: _headers,
          body: jsonEncode({'name': name, 'email': email ?? ''}),
        )
        .timeout(kColdStartTimeout);
    final data = _decode(response);
    if (response.statusCode == 200 && data['user'] != null) {
      final user = AppUser.fromJson(data['user'] as Map<String, dynamic>);
      await _storeSession(_token!, user);
      return user;
    }
    throw ApiException(
      data['message']?.toString() ?? 'Mise à jour impossible',
      statusCode: response.statusCode,
    );
  }

  Future<void> logout() async {
    _token = null;
    _user = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
  }
}
