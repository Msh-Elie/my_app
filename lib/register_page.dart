import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api_client.dart';
import 'login_page.dart' show AuthTextField;
import 'theme.dart';
import 'ui_kit.dart';

class RegisterPage extends StatefulWidget {
  final VoidCallback? onAuthenticated;

  const RegisterPage({super.key, this.onAuthenticated});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final nameController = TextEditingController();
  final phoneController = TextEditingController();
  final emailController = TextEditingController();
  final pinController = TextEditingController();
  final pinConfirmController = TextEditingController();
  bool submitting = false;
  bool obscurePin = true;
  String? errorMessage;

  @override
  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    emailController.dispose();
    pinController.dispose();
    pinConfirmController.dispose();
    super.dispose();
  }

  String? _validate() {
    final name = nameController.text.trim();
    final phone = phoneController.text.replaceAll(RegExp(r'[^0-9]'), '');
    final email = emailController.text.trim();
    final pin = pinController.text.trim();
    final confirm = pinConfirmController.text.trim();

    if (name.length < 2) return 'Entrez votre nom complet';
    if (phone.length < 8 || phone.length > 15) {
      return 'Numéro invalide — indicatif inclus, ex: 22951469075';
    }
    if (email.isNotEmpty && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return 'Adresse e-mail invalide';
    }
    if (pin.length < 4 || pin.length > 8) return 'Le PIN doit contenir 4 à 8 chiffres';
    if (pin != confirm) return 'Les deux PIN ne correspondent pas';
    return null;
  }

  Future<void> _submit() async {
    final validation = _validate();
    if (validation != null) {
      setState(() => errorMessage = validation);
      return;
    }

    setState(() {
      submitting = true;
      errorMessage = null;
    });

    try {
      await ApiClient.instance.register(
        name: nameController.text.trim(),
        phone: phoneController.text.replaceAll(RegExp(r'[^0-9]'), ''),
        pin: pinController.text.trim(),
        email: emailController.text.trim(),
      );
      if (!mounted) return;
      // Retire l'écran d'inscription de la pile puis notifie l'AuthGate.
      Navigator.of(context).popUntil((route) => route.isFirst);
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
      appBar: AppBar(title: const Text('Créer un compte')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.sm,
              AppSpacing.xl,
              AppSpacing.xxl,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Créez votre compte en une minute.',
                    style: context.text.headlineSmall,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Vos informations restent sur votre serveur SwitchMoney.',
                    style: context.text.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  AuthTextField(
                    controller: nameController,
                    label: 'Nom complet',
                    hint: 'ex: MENSAH Elie',
                    prefixIcon: Icons.person_outline_rounded,
                  ),
                  const SizedBox(height: AppSpacing.lg),
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
                    controller: emailController,
                    label: 'E-mail (optionnel)',
                    keyboardType: TextInputType.emailAddress,
                    prefixIcon: Icons.mail_outline_rounded,
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
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  AuthTextField(
                    controller: pinConfirmController,
                    label: 'Confirmez le PIN',
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(8),
                    ],
                    prefixIcon: Icons.lock_outline_rounded,
                    obscureText: obscurePin,
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
                    label: 'Créer mon compte',
                    loading: submitting,
                    onPressed: _submit,
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
