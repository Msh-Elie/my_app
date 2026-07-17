import 'package:flutter/material.dart';

import 'api_client.dart';

const Color _accent = Color(0xFFFE6F0B);

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late final TextEditingController nameController;
  late final TextEditingController emailController;
  bool saving = false;
  String? feedback;
  bool feedbackIsError = false;

  AppUser? get user => ApiClient.instance.user;

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController(text: user?.name ?? '');
    emailController = TextEditingController(text: user?.email ?? '');
    // Rafraîchit le profil depuis le serveur en arrière-plan.
    ApiClient.instance.fetchMe().then((refreshed) {
      if (!mounted || refreshed == null) return;
      setState(() {
        if (nameController.text.isEmpty) nameController.text = refreshed.name;
        if (emailController.text.isEmpty) {
          emailController.text = refreshed.email ?? '';
        }
      });
    });
  }

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = nameController.text.trim();
    if (name.length < 2) {
      setState(() {
        feedback = 'Le nom doit contenir au moins 2 caractères';
        feedbackIsError = true;
      });
      return;
    }

    setState(() {
      saving = true;
      feedback = null;
    });

    try {
      await ApiClient.instance.updateProfile(
        name: name,
        email: emailController.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        feedback = 'Profil mis à jour';
        feedbackIsError = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        feedback = e.message;
        feedbackIsError = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        feedback = 'Serveur injoignable';
        feedbackIsError = true;
      });
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profil'),
        backgroundColor: Colors.black,
      ),
      backgroundColor: Colors.black,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            const CircleAvatar(
              radius: 38,
              backgroundColor: _accent,
              child: Icon(Icons.person, color: Colors.black, size: 42),
            ),
            const SizedBox(height: 14),
            Text(
              user?.name ?? 'Utilisateur',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              user != null ? '+${user!.phone}' : '',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 14),
            ),
            const SizedBox(height: 28),
            TextField(
              controller: nameController,
              style: const TextStyle(color: Colors.white),
              cursorColor: _accent,
              decoration: _fieldDecoration('Nom complet'),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              style: const TextStyle(color: Colors.white),
              cursorColor: _accent,
              decoration: _fieldDecoration('E-mail (optionnel)'),
            ),
            const SizedBox(height: 8),
            const Text(
              'Le numéro de téléphone est votre identifiant de connexion et ne peut pas être modifié.',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
            if (feedback != null) ...[
              const SizedBox(height: 14),
              Text(
                feedback!,
                style: TextStyle(
                  color: feedbackIsError
                      ? const Color(0xFFFF8A80)
                      : const Color(0xFF33D17A),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 22),
            ElevatedButton(
              onPressed: saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28)),
                textStyle: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold),
              ),
              child: saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black),
                    )
                  : const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration(String label) {
    return InputDecoration(
      filled: true,
      fillColor: const Color(0xFF1C1C1C),
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white70, fontSize: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0x44FE6F0B)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _accent, width: 2),
      ),
    );
  }
}
