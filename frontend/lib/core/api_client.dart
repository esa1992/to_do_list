import "dart:convert";
import "dart:io";
import "package:flutter/foundation.dart";
import "package:http/io_client.dart";
import "proxy_settings.dart";

class ApiClient {
  final String baseUrl;
  final String? token;
  final ProxySettings proxySettings;

  ApiClient({
    required this.baseUrl,
    required this.proxySettings,
    this.token,
  });

  IOClient _buildClient() {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 45);
    if (proxySettings.isEnabled) {
      client.findProxy = (_) => proxySettings.asProxyDirective();
      if (proxySettings.insecureTlsProxyMode) {
        // Compatibility mode for corporate proxies that break revocation checks.
        // Security is reduced: any certificate is accepted while proxy is enabled.
        client.badCertificateCallback = (_cert, _host, _port) => true;
      }
    }
    return IOClient(client);
  }

  void _logRequest(String method, String path) {
    if (kDebugMode) {
      debugPrint("[API] -> $method $baseUrl$path");
    }
  }

  void _logResponse(String method, String path, int statusCode) {
    if (kDebugMode) {
      debugPrint("[API] <- $method $path [$statusCode]");
    }
  }

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) async {
    _logRequest("POST", path);
    final client = _buildClient();
    final res = await client.post(
      Uri.parse("$baseUrl$path"),
      headers: {
        HttpHeaders.contentTypeHeader: "application/json",
        if (token != null) HttpHeaders.authorizationHeader: "Bearer $token",
      },
      body: jsonEncode(body),
    );
    _logResponse("POST", path, res.statusCode);
    if (res.statusCode >= 400) throw Exception("HTTP ${res.statusCode}: ${res.body}");
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> patch(String path, Map<String, dynamic> body) async {
    _logRequest("PATCH", path);
    final client = _buildClient();
    final res = await client.patch(
      Uri.parse("$baseUrl$path"),
      headers: {
        HttpHeaders.contentTypeHeader: "application/json",
        if (token != null) HttpHeaders.authorizationHeader: "Bearer $token",
      },
      body: jsonEncode(body),
    );
    _logResponse("PATCH", path, res.statusCode);
    if (res.statusCode >= 400) throw Exception("HTTP ${res.statusCode}: ${res.body}");
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> delete(String path) async {
    _logRequest("DELETE", path);
    final client = _buildClient();
    final res = await client.delete(
      Uri.parse("$baseUrl$path"),
      headers: {
        if (token != null) HttpHeaders.authorizationHeader: "Bearer $token",
      },
    );
    _logResponse("DELETE", path, res.statusCode);
    if (res.statusCode >= 400) throw Exception("HTTP ${res.statusCode}: ${res.body}");
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<List<dynamic>> getList(String path) async {
    _logRequest("GET", path);
    final client = _buildClient();
    final res = await client.get(
      Uri.parse("$baseUrl$path"),
      headers: {
        if (token != null) HttpHeaders.authorizationHeader: "Bearer $token",
      },
    );
    _logResponse("GET", path, res.statusCode);
    if (res.statusCode >= 400) throw Exception("HTTP ${res.statusCode}: ${res.body}");
    return jsonDecode(res.body) as List<dynamic>;
  }

  Future<Map<String, dynamic>> getMap(String path) async {
    _logRequest("GET", path);
    final client = _buildClient();
    final res = await client.get(
      Uri.parse("$baseUrl$path"),
      headers: {
        if (token != null) HttpHeaders.authorizationHeader: "Bearer $token",
      },
    );
    _logResponse("GET", path, res.statusCode);
    if (res.statusCode >= 400) throw Exception("HTTP ${res.statusCode}: ${res.body}");
    return jsonDecode(res.body) as Map<String, dynamic>;
  }
}
