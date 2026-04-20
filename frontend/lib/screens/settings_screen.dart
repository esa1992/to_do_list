import "package:flutter/material.dart";
import "package:provider/provider.dart";
import "../core/auth_store.dart";
import "../core/proxy_settings.dart";

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController ipCtrl;
  late final TextEditingController portCtrl;
  late final TextEditingController loginCtrl;
  late final TextEditingController passCtrl;
  bool insecureTlsProxyMode = false;

  @override
  void initState() {
    super.initState();
    final proxy = context.read<AuthStore>().proxy;
    ipCtrl = TextEditingController(text: proxy.ip);
    portCtrl = TextEditingController(text: proxy.port == 0 ? "" : proxy.port.toString());
    loginCtrl = TextEditingController(text: proxy.login ?? "");
    passCtrl = TextEditingController(text: proxy.password ?? "");
    insecureTlsProxyMode = proxy.insecureTlsProxyMode;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Сетевые настройки"),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: ipCtrl, decoration: const InputDecoration(labelText: "IP")),
            TextField(controller: portCtrl, decoration: const InputDecoration(labelText: "Port")),
            TextField(controller: loginCtrl, decoration: const InputDecoration(labelText: "Login")),
            TextField(controller: passCtrl, decoration: const InputDecoration(labelText: "Password")),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text("Режим совместимости TLS"),
              subtitle: const Text(
                "Использовать только в корпоративных прокси-сетях,\nгде обычная TLS-проверка не проходит.",
              ),
              value: insecureTlsProxyMode,
              onChanged: (v) => setState(() => insecureTlsProxyMode = v),
            ),
            if (insecureTlsProxyMode)
              const Text(
                "Внимание: в этом режиме проверка сертификатов ослабляется.",
                style: TextStyle(color: Colors.orangeAccent, fontSize: 12),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Отмена")),
        FilledButton(
          onPressed: () async {
            final store = context.read<AuthStore>();
            await store.saveProxy(
              ProxySettings(
                ip: ipCtrl.text.trim(),
                port: int.tryParse(portCtrl.text.trim()) ?? 0,
                login: loginCtrl.text.trim().isEmpty ? null : loginCtrl.text.trim(),
                password: passCtrl.text.trim().isEmpty ? null : passCtrl.text.trim(),
                insecureTlsProxyMode: insecureTlsProxyMode,
              ),
            );
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text("Сохранить"),
        ),
      ],
    );
  }
}
