import "package:flutter/material.dart";
import "package:provider/provider.dart";
import "../core/api_client.dart";
import "../core/auth_store.dart";
import "settings_screen.dart";

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final loginCtrl = TextEditingController();
  final passCtrl = TextEditingController();
  bool isRegister = false;
  bool loading = false;
  bool checkingConnection = false;
  String? error;

  String _normalizeAuthError(Object e) {
    final msg = e.toString();
    final lower = msg.toLowerCase();
    if (lower.contains("socketexception") ||
        lower.contains("failed host lookup") ||
        lower.contains("connection failed") ||
        lower.contains("operation not permitted")) {
      return "Сетевая ошибка. Если вы работаете через прокси, сначала откройте 'Сеть / Прокси' и сохраните настройки.";
    }
    if (lower.contains("certificate_verify_failed") ||
        lower.contains("handshakeexception") ||
        lower.contains("crypt_e_no_revocation_check")) {
      return "TLS/сертификат не прошел проверку через прокси. Включите 'Режим совместимости TLS' в 'Сеть / Прокси'.";
    }
    return msg;
  }

  Future<void> submit() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final auth = context.read<AuthStore>();
      if (isRegister) {
        await auth.register(loginCtrl.text.trim(), passCtrl.text);
      } else {
        await auth.loginWithCredentials(loginCtrl.text.trim(), passCtrl.text);
      }
    } catch (e) {
      setState(() => error = _normalizeAuthError(e));
    } finally {
      setState(() => loading = false);
    }
  }

  Future<void> openProxySettings() async {
    await showDialog(
      context: context,
      builder: (_) => const SettingsScreen(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Сетевые настройки сохранены")),
    );
  }

  Future<void> checkConnection() async {
    setState(() => checkingConnection = true);
    try {
      final auth = context.read<AuthStore>();
      final api = ApiClient(
        baseUrl: auth.baseUrl,
        proxySettings: auth.proxy,
      );
      final health = await api.getMap("/health");
      if (!mounted) return;
      final ok = health["ok"] == true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? "Соединение успешно: сервер доступен" : "Сервер ответил, но статус не OK"),
          backgroundColor: ok ? Colors.green.shade700 : Colors.orange.shade800,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Ошибка соединения: ${_normalizeAuthError(e)}"),
          backgroundColor: Colors.orange.shade800,
        ),
      );
    } finally {
      if (mounted) setState(() => checkingConnection = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: "Сеть / Прокси",
            onPressed: loading ? null : openProxySettings,
            icon: const Icon(Icons.settings_ethernet),
          ),
          IconButton(
            tooltip: checkingConnection ? "Проверка..." : "Проверить соединение",
            onPressed: (loading || checkingConnection) ? null : checkConnection,
            icon: Icon(checkingConnection ? Icons.sync : Icons.wifi_tethering),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(isRegister ? "Регистрация" : "Вход", style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 16),
                TextField(controller: loginCtrl, decoration: const InputDecoration(labelText: "Логин")),
                const SizedBox(height: 12),
                TextField(controller: passCtrl, decoration: const InputDecoration(labelText: "Пароль"), obscureText: true),
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Text(error!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 16),
                FilledButton(onPressed: loading ? null : submit, child: Text(loading ? "..." : (isRegister ? "Создать аккаунт" : "Войти"))),
                TextButton(
                  onPressed: loading ? null : () => setState(() => isRegister = !isRegister),
                  child: Text(isRegister ? "Уже есть аккаунт? Войти" : "Нет аккаунта? Регистрация"),
                ),
                const SizedBox(height: 6),
                const Text(
                  "Если интернет доступен только через прокси,\nнастройте его перед входом.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
