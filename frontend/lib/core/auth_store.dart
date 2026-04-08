import "package:flutter/foundation.dart";
import "package:flutter_secure_storage/flutter_secure_storage.dart";
import "api_client.dart";
import "proxy_settings.dart";

class AuthStore extends ChangeNotifier {
  static const _tokenKey = "auth_token";
  static const _refreshTokenKey = "refresh_token";
  static const _loginKey = "login";
  final _storage = const FlutterSecureStorage();
  final proxyStore = ProxySettingsStore();

  String? token;
  String? refreshToken;
  String? login;
  ProxySettings proxy = const ProxySettings(ip: "", port: 0);
  final String baseUrl;

  AuthStore({required this.baseUrl});

  Future<void> init() async {
    token = await _storage.read(key: _tokenKey);
    refreshToken = await _storage.read(key: _refreshTokenKey);
    login = await _storage.read(key: _loginKey);
    proxy = await proxyStore.load();
    notifyListeners();
  }

  Future<void> loginWithCredentials(String userLogin, String password) async {
    final api = ApiClient(baseUrl: baseUrl, proxySettings: proxy);
    final data = await api.post("/api/auth/login", {"login": userLogin, "password": password});
    token = data["token"] as String;
    refreshToken = data["refreshToken"] as String?;
    login = (data["user"] as Map<String, dynamic>)["login"] as String;
    await _storage.write(key: _tokenKey, value: token);
    await _storage.write(key: _refreshTokenKey, value: refreshToken);
    await _storage.write(key: _loginKey, value: login);
    notifyListeners();
  }

  Future<void> register(String userLogin, String password) async {
    final api = ApiClient(baseUrl: baseUrl, proxySettings: proxy);
    final data = await api.post("/api/auth/register", {"login": userLogin, "password": password});
    token = data["token"] as String;
    refreshToken = data["refreshToken"] as String?;
    login = (data["user"] as Map<String, dynamic>)["login"] as String;
    await _storage.write(key: _tokenKey, value: token);
    await _storage.write(key: _refreshTokenKey, value: refreshToken);
    await _storage.write(key: _loginKey, value: login);
    notifyListeners();
  }

  Future<void> refreshSessionIfNeeded() async {
    if (token != null || refreshToken == null || login == null) return;
    final api = ApiClient(baseUrl: baseUrl, proxySettings: proxy);
    final data = await api.post("/api/auth/refresh", {"login": login, "refreshToken": refreshToken});
    token = data["token"] as String;
    refreshToken = data["refreshToken"] as String?;
    await _storage.write(key: _tokenKey, value: token);
    await _storage.write(key: _refreshTokenKey, value: refreshToken);
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
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _refreshTokenKey);
    await _storage.delete(key: _loginKey);
    notifyListeners();
  }

  Future<void> saveProxy(ProxySettings settings) async {
    proxy = settings;
    await proxyStore.save(settings);
    notifyListeners();
  }
}
