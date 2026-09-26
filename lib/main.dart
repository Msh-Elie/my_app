import 'package:flutter/material.dart';

import 'api_client.dart';
import 'home_page.dart';
import 'login_page.dart';
import 'theme.dart';
import 'theme_controller.dart';
import 'ui_kit.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeController = ThemeController.instance;

    // Le thème est reconstruit à chaque changement de préférence : la bascule
    // clair/sombre est donc immédiate, sans redémarrage de l'application.
    return AnimatedBuilder(
      animation: themeController,
      builder: (context, _) {
        return MaterialApp(
          title: 'SwitchMoney',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: themeController.mode,
          home: const AuthGate(),
        );
      },
    );
  }
}

/// Charge la session stockée puis affiche soit l'app, soit l'écran de
/// connexion. `refresh()` est rappelé après connexion/déconnexion.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

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
    // Le thème enregistré est restitué avant le premier écran pour éviter
    // un flash clair au lancement chez les utilisateurs en mode sombre.
    await ThemeController.instance.load();
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
    if (!ready) return const _SplashScreen();

    if (!ApiClient.instance.isLoggedIn) {
      return LoginPage(onAuthenticated: refresh);
    }

    return HomePage(onLoggedOut: refresh);
  }
}

/// Écran d'attente affiché le temps de restaurer la session.
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BrandMark(size: 56, showWordmark: false),
            const SizedBox(height: AppSpacing.lg),
            Text('SwitchMoney', style: context.text.headlineSmall),
            const SizedBox(height: AppSpacing.xl),
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: context.colors.brand,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
