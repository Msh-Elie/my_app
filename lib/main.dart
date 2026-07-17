import 'package:flutter/material.dart';

import 'api_client.dart';
import 'home_page.dart';
import 'login_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  ThemeMode themeMode = ThemeMode.dark;

  void setThemeMode(ThemeMode mode) {
    setState(() {
      themeMode = mode;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.light().copyWith(
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(backgroundColor: Colors.black),
      ),
      darkTheme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        appBarTheme: const AppBarTheme(backgroundColor: Colors.black),
      ),
      themeMode: themeMode,
      home: AuthGate(themeMode: themeMode, onThemeChange: setThemeMode),
    );
  }
}

/// Charge la session stockée puis affiche soit l'app, soit l'écran de
/// connexion. `refresh()` est rappelé après connexion/déconnexion.
class AuthGate extends StatefulWidget {
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeChange;

  const AuthGate({
    super.key,
    required this.themeMode,
    required this.onThemeChange,
  });

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool ready = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await ApiClient.instance.init();
    if (!mounted) return;
    setState(() => ready = true);
    // Rafraîchit le profil en arrière-plan ; déconnecte si le jeton est rejeté.
    if (ApiClient.instance.isLoggedIn) {
      ApiClient.instance.fetchMe().then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!ready) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFFFE6F0B)),
        ),
      );
    }

    if (!ApiClient.instance.isLoggedIn) {
      return LoginPage(onAuthenticated: refresh);
    }

    return HomePage(
      themeMode: widget.themeMode,
      onThemeChange: widget.onThemeChange,
      onLoggedOut: refresh,
    );
  }
}
