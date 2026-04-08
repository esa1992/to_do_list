import "dart:convert";
import "dart:io";
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
    if (proxySettings.isEnabled) {
      client.findProxy = (_) => proxySettings.asProxyDirective();
    }
    return IOClient(client);
  }

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) async {
    final client = _buildClient();
    final res = await client.post(
      Uri.parse("$baseUrl$path"),
      headers: {
        HttpHeaders.contentTypeHeader: "application/json",
        if (token != null) HttpHeaders.authorizationHeader: "Bearer $token",
      },
      body: jsonEncode(body),
    );
    if (res.statusCode >= 400) throw Exception("HTTP ${res.statusCode}: ${res.body}");
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> patch(String path, Map<String, dynamic> body) async {
    final client = _buildClient();
    final res = await client.patch(
      Uri.parse("$baseUrl$path"),
      headers: {
        HttpHeaders.contentTypeHeader: "application/json",
        if (token != null) HttpHeaders.authorizationHeader: "Bearer $token",
      },
      body: jsonEncode(body),
    );
    if (res.statusCode >= 400) throw Exception("HTTP ${res.statusCode}: ${res.body}");
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> delete(String path) async {
    final client = _buildClient();
    final res = await client.delete(
      Uri.parse("$baseUrl$path"),
      headers: {
        if (token != null) HttpHeaders.authorizationHeader: "Bearer $token",
      },
    );
    if (res.statusCode >= 400) throw Exception("HTTP ${res.statusCode}: ${res.body}");
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<List<dynamic>> getList(String path) async {
    final client = _buildClient();
    final res = await client.get(
      Uri.parse("$baseUrl$path"),
      headers: {
        if (token != null) HttpHeaders.authorizationHeader: "Bearer $token",
      },
    );
    if (res.statusCode >= 400) throw Exception("HTTP ${res.statusCode}: ${res.body}");
    return jsonDecode(res.body) as List<dynamic>;
  }

  Future<Map<String, dynamic>> getMap(String path) async {
    final client = _buildClient();
    final res = await client.get(
      Uri.parse("$baseUrl$path"),
      headers: {
        if (token != null) HttpHeaders.authorizationHeader: "Bearer $token",
      },
    );
    if (res.statusCode >= 400) throw Exception("HTTP ${res.statusCode}: ${res.body}");
    return jsonDecode(res.body) as Map<String, dynamic>;
  }
}
