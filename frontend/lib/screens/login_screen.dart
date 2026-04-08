import "package:flutter/material.dart";
import "package:provider/provider.dart";
import "../core/auth_store.dart";

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
  String? error;

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
      setState(() => error = e.toString());
    } finally {
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}
