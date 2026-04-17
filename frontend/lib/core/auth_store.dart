import "package:flutter/foundation.dart";
import "package:shared_preferences/shared_preferences.dart";
import "api_client.dart";
import "proxy_settings.dart";

class AuthStore extends ChangeNotifier {
  static const _tokenKey = "auth_token";
  static const _refreshTokenKey = "refresh_token";
  static const _loginKey = "login";
  final proxyStore = ProxySettingsStore();

  String? token;
  String? refreshToken;
  String? login;
  ProxySettings proxy = const ProxySettings(ip: "", port: 0);
  final String baseUrl;

  AuthStore({required this.baseUrl});

  Future<void> _save(String key, String? value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value == null) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, value);
    }
  }

  Future<String?> _read(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key);
  }

  Future<void> _delete(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }

  Future<void> init() async {
    token = await _read(_tokenKey);
    refreshToken = await _read(_refreshTokenKey);
    login = await _read(_loginKey);
    proxy = await proxyStore.load();
    notifyListeners();
  }

  Future<void> loginWithCredentials(String userLogin, String password) async {
    final api = ApiClient(baseUrl: baseUrl, proxySettings: proxy);
    final data = await api.post("/api/auth/login", {"login": userLogin, "password": password});
    token = data["token"] as String;
    refreshToken = data["refreshToken"] as String?;
    login = (data["user"] as Map<String, dynamic>)["login"] as String;
    await _save(_tokenKey, token);
    await _save(_refreshTokenKey, refreshToken);
    await _save(_loginKey, login);
    notifyListeners();
  }

  Future<void> register(String userLogin, String password) async {
    final api = ApiClient(baseUrl: baseUrl, proxySettings: proxy);
    final data = await api.post("/api/auth/register", {"login": userLogin, "password": password});
    token = data["token"] as String;
    refreshToken = data["refreshToken"] as String?;
    login = (data["user"] as Map<String, dynamic>)["login"] as String;
    await _save(_tokenKey, token);
    await _save(_refreshTokenKey, refreshToken);
    await _save(_loginKey, login);
    notifyListeners();
  }

  Future<void> refreshSessionIfNeeded() async {
    if (token != null || refreshToken == null || login == null) return;
    final api = ApiClient(baseUrl: baseUrl, proxySettings: proxy);
    final data = await api.post("/api/auth/refresh", {"login": login, "refreshToken": refreshToken});
    token = data["token"] as String;
    refreshToken = data["refreshToken"] as String?;
    await _save(_tokenKey, token);
    await _save(_refreshTokenKey, refreshToken);
    notifyListeners();
  }

  Future<void> logout() async {
    final currentLogin = login;
    token = null;
    refreshToken = null;
    login = null;
    if (currentLogin != null) {
      final api = ApiClient(baseUrl: baseUrl, proxySettings: proxy);
      await api.post("/api/auth/logout", {"login": currentLogin});
    }
    await _delete(_tokenKey);
    await _delete(_refreshTokenKey);
    await _delete(_loginKey);
    notifyListeners();
  }

  Future<void> saveProxy(ProxySettings settings) async {
    proxy = settings;
    await proxyStore.save(settings);
    notifyListeners();
  }
}
