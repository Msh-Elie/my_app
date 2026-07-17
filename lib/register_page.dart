import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api_client.dart';
import 'login_page.dart' show AuthTextField;

const Color _accent = Color(0xFFFE6F0B);

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
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Créer un compte',
            style: TextStyle(color: Colors.white)),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Vos informations restent sur votre serveur SwitchMoney.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white60, fontSize: 13),
                  ),
                  const SizedBox(height: 24),
                  AuthTextField(
                    controller: nameController,
                    label: 'Nom complet',
                    hint: 'ex: MENSAH Elie',
                    prefixIcon: Icons.person_outline,
                  ),
                  const SizedBox(height: 14),
                  AuthTextField(
                    controller: phoneController,
                    label: 'Numéro de téléphone (avec indicatif)',
                    hint: 'ex: 22951469075',
                    keyboardType: TextInputType.phone,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    prefixIcon: Icons.phone_android,
                  ),
                  const SizedBox(height: 14),
                  AuthTextField(
                    controller: emailController,
                    label: 'E-mail (optionnel)',
                    keyboardType: TextInputType.emailAddress,
                    prefixIcon: Icons.mail_outline,
                  ),
                  const SizedBox(height: 14),
                  AuthTextField(
                    controller: pinController,
                    label: 'Code PIN (4 à 8 chiffres)',
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
                  ),
                  const SizedBox(height: 14),
                  AuthTextField(
                    controller: pinConfirmController,
                    label: 'Confirmez le PIN',
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(8),
                    ],
                    prefixIcon: Icons.lock_outline,
                    obscureText: obscurePin,
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
                        : const Text('Créer mon compte'),
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
