import "dart:convert";
import "package:shared_preferences/shared_preferences.dart";

class ProxySettings {
  final String ip;
  final int port;
  final String? login;
  final String? password;
  final bool insecureTlsProxyMode;

  const ProxySettings({
    required this.ip,
    required this.port,
    this.login,
    this.password,
    this.insecureTlsProxyMode = false,
  });

  bool get isEnabled => ip.isNotEmpty && port > 0;

  String asProxyDirective() {
    final creds = (login?.isNotEmpty == true && password?.isNotEmpty == true)
        ? "$login:$password@"
        : "";
    return "PROXY $creds$ip:$port";
  }

  Map<String, dynamic> toJson() => {
        "ip": ip,
        "port": port,
        "login": login,
        "password": password,
        "insecureTlsProxyMode": insecureTlsProxyMode,
      };

  factory ProxySettings.fromJson(Map<String, dynamic> json) {
    return ProxySettings(
      ip: (json["ip"] ?? "") as String,
      port: (json["port"] ?? 0) as int,
      login: json["login"] as String?,
      password: json["password"] as String?,
      insecureTlsProxyMode: (json["insecureTlsProxyMode"] ?? false) as bool,
    );
  }
}

class ProxySettingsStore {
  static const _key = "proxy_settings_v1";

  Future<void> save(ProxySettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(settings.toJson()));
  }

  Future<ProxySettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return const ProxySettings(ip: "", port: 0);
    return ProxySettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }
}
