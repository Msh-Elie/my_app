import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api_client.dart';
import 'register_page.dart';
import 'server_settings_sheet.dart';

const Color _accent = Color(0xFFFE6F0B);

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
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 12),
                  const Icon(Icons.swap_horiz_rounded, color: _accent, size: 64),
                  const SizedBox(height: 12),
                  const Text(
                    'SwitchMoney',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Connectez-vous pour envoyer de l\'argent',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white60, fontSize: 14),
                  ),
                  const SizedBox(height: 36),
                  AuthTextField(
                    controller: phoneController,
                    label: 'Numéro de téléphone (avec indicatif)',
                    hint: 'ex: 22951469075',
                    keyboardType: TextInputType.phone,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    prefixIcon: Icons.phone_android,
                  ),
                  const SizedBox(height: 16),
                  AuthTextField(
                    controller: pinController,
                    label: 'Code PIN',
                    hint: '4 à 8 chiffres',
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(8),
                    ],
                    prefixIcon: Icons.lock_outline,
                    obscureText: obscurePin,
                    suffix: IconButton(
                      icon: Icon(
                        obscurePin ? Icons.visibility_off : Icons.visibility,
                        color: Colors.white38,
                        size: 20,
                      ),
                      onPressed: () => setState(() => obscurePin = !obscurePin),
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                  if (errorMessage != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0x22FF5252),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0x66FF5252)),
                      ),
                      child: Text(
                        errorMessage!,
                        style: const TextStyle(
                            color: Color(0xFFFF8A80), fontSize: 13),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: submitting ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accent,
                      foregroundColor: Colors.black,
                      disabledBackgroundColor: Colors.grey,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30)),
                      textStyle: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    child: submitting
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.black),
                          )
                        : const Text('Se connecter'),
                  ),
                  const SizedBox(height: 18),
                  TextButton(
                    onPressed: submitting
                        ? null
                        : () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => RegisterPage(
                                    onAuthenticated: widget.onAuthenticated),
                              ),
                            );
                          },
                    child: const Text.rich(
                      TextSpan(
                        text: 'Pas encore de compte ? ',
                        style: TextStyle(color: Colors.white60),
                        children: [
                          TextSpan(
                            text: 'Créer un compte',
                            style: TextStyle(
                                color: _accent, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () => showServerSettingsSheet(context),
                    icon: const Icon(Icons.dns_outlined,
                        color: Colors.white38, size: 18),
                    label: const Text(
                      'Serveur backend',
                      style: TextStyle(color: Colors.white38, fontSize: 13),
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
      style: const TextStyle(
          color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
      cursorColor: _accent,
      decoration: InputDecoration(
        filled: true,
        fillColor: const Color(0xFF1C1C1C),
        labelText: label,
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white24),
        labelStyle: const TextStyle(color: Colors.white70, fontSize: 14),
        prefixIcon: prefixIcon != null
            ? Icon(prefixIcon, color: Colors.white38, size: 20)
            : null,
        suffixIcon: suffix,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _accent),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0x44FE6F0B)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _accent, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      ),
    );
  }
}
