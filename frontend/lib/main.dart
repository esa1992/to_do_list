import "package:flutter/material.dart";
import "package:provider/provider.dart";
import "core/auth_store.dart";
import "screens/login_screen.dart";
import "screens/tasks_screen.dart";

const apiBaseUrl = String.fromEnvironment(
  "API_BASE_URL",
  defaultValue: "https://to-do-list-backend-yrwf.onrender.com",
);

void main() {
  runApp(const RootApp());
}

class RootApp extends StatelessWidget {
  const RootApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) {
        final store = AuthStore(baseUrl: apiBaseUrl);
        store.init().then((_) => store.refreshSessionIfNeeded());
        return store;
      },
      child: MaterialApp(
        title: "Cross ToDo",
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.dark,
        darkTheme: ThemeData(
          brightness: Brightness.dark,
          useMaterial3: true,
          colorSchemeSeed: Colors.teal,
        ),
        home: const _AuthGate(),
      ),
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthStore>();
    if (auth.token == null) return const LoginScreen();
    return const TasksScreen();
  }
}
