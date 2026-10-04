import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api_client.dart';
import 'register_page.dart';
import 'theme.dart';
import 'ui_kit.dart';

class LoginPage extends StatefulWidget {
  /// Appelé quand la connexion réussit (l'AuthGate rebascule sur l'app).
  final VoidCallback? onAuthenticated;

  const LoginPage({super.key, this.onAuthenticated});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final phoneController = TextEditingController();
  final pinController = TextEditingController();
  bool submitting = false;
  bool obscurePin = true;
  String? errorMessage;

  @override
  void dispose() {
    phoneController.dispose();
    pinController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final phone = phoneController.text.replaceAll(RegExp(r'[^0-9]'), '');
    final pin = pinController.text.trim();

    if (phone.length < 8) {
      setState(() => errorMessage =
          'Entrez votre numéro complet avec l\'indicatif (ex: 22951469075)');
      return;
    }
    if (pin.length < 4) {
      setState(() => errorMessage = 'PIN de 4 chiffres minimum');
      return;
    }

    setState(() {
      submitting = true;
      errorMessage = null;
    });

    try {
      await ApiClient.instance.login(phone: phone, pin: pin);
      if (!mounted) return;
      widget.onAuthenticated?.call();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => errorMessage = e.message);
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl,
              vertical: AppSpacing.xl,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: AppSpacing.md),
                  const Center(child: BrandMark(size: 60, showWordmark: false)),
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    'Bon retour',
                    textAlign: TextAlign.center,
                    style: context.text.displaySmall,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Connectez-vous pour envoyer de l\'argent\nentre opérateurs mobile money.',
                    textAlign: TextAlign.center,
                    style: context.text.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  AuthTextField(
                    controller: phoneController,
                    label: 'Numéro de téléphone',
                    hint: '22951469075',
                    keyboardType: TextInputType.phone,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    prefixIcon: Icons.phone_iphone_rounded,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  AuthTextField(
                    controller: pinController,
                    label: 'Code PIN',
                    hint: '4 à 8 chiffres',
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(8),
                    ],
                    prefixIcon: Icons.lock_outline_rounded,
                    obscureText: obscurePin,
                    suffix: IconButton(
                      icon: Icon(
                        obscurePin
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: context.colors.textMuted,
                        size: 20,
                      ),
                      onPressed: () => setState(() => obscurePin = !obscurePin),
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                  if (errorMessage != null) ...[
                    const SizedBox(height: AppSpacing.lg),
                    InfoBanner(
                      message: errorMessage!,
                      tone: Tone.danger,
                      icon: Icons.error_outline_rounded,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  PrimaryButton(
                    label: 'Se connecter',
                    loading: submitting,
                    onPressed: _submit,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  TextButton(
                    onPressed: submitting
                        ? null
                        : () {
                            Navigator.push(
                              context,
                              appRoute(RegisterPage(
                                  onAuthenticated: widget.onAuthenticated)),
                            );
                          },
                    child: Text.rich(
                      TextSpan(
                        text: 'Pas encore de compte ? ',
                        style: context.text.bodyMedium,
                        children: [
                          TextSpan(
                            text: 'Créer un compte',
                            style: context.text.bodyMedium?.copyWith(
                              color: context.colors.brandText,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Champ de saisie partagé par les écrans de connexion/inscription.
///
/// L'habillage (fond, contour, focus) vient du thème : ce widget n'ajoute que
/// le libellé, l'icône et les règles de saisie.
class AuthTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final IconData? prefixIcon;
  final bool obscureText;
  final Widget? suffix;
  final ValueChanged<String>? onSubmitted;

  const AuthTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.keyboardType,
    this.inputFormatters,
    this.prefixIcon,
    this.obscureText = false,
    this.suffix,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      obscureText: obscureText,
      onSubmitted: onSubmitted,
      style: context.text.bodyLarge?.copyWith(
        fontWeight: FontWeight.w600,
        fontSize: 16,
        fontFeatures: keyboardType == TextInputType.phone ? kTabularFigures : null,
      ),
      cursorColor: context.colors.brand,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: prefixIcon != null
            ? Icon(prefixIcon, color: context.colors.textMuted, size: 20)
            : null,
        suffixIcon: suffix,
      ),
    );
  }
}
