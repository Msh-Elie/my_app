import 'package:flutter/material.dart';

import 'api_client.dart';
import 'theme.dart';
import 'ui_kit.dart';

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
    final c = context.colors;

    return Scaffold(
      appBar: AppBar(title: const Text('Profil')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.xxl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Bandeau d'identité
            AppCard(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.xl,
              ),
              child: Column(
                children: [
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFF8A3D), kBrand],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      boxShadow: [
                        BoxShadow(
                          color: kBrand.withValues(alpha: 0.28),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Icon(Icons.person_rounded,
                        color: c.onBrand, size: 38),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    user?.name ?? 'Utilisateur',
                    textAlign: TextAlign.center,
                    style: context.text.headlineSmall,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    user != null ? '+${user!.phone}' : '',
                    textAlign: TextAlign.center,
                    style: context.text.bodyMedium?.copyWith(
                      fontFeatures: kTabularFigures,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.xl),
            const SectionLabel('Informations personnelles'),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: nameController,
                    style: context.text.bodyLarge,
                    cursorColor: c.brand,
                    decoration: const InputDecoration(labelText: 'Nom complet'),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    style: context.text.bodyLarge,
                    cursorColor: c.brand,
                    decoration:
                        const InputDecoration(labelText: 'E-mail (optionnel)'),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Le numéro de téléphone est votre identifiant de connexion '
                    'et ne peut pas être modifié.',
                    style: context.text.bodySmall,
                  ),
                ],
              ),
            ),

            if (feedback != null) ...[
              const SizedBox(height: AppSpacing.lg),
              InfoBanner(
                message: feedback!,
                tone: feedbackIsError ? Tone.danger : Tone.success,
                icon: feedbackIsError
                    ? Icons.error_outline_rounded
                    : Icons.check_circle_outline_rounded,
              ),
            ],

            const SizedBox(height: AppSpacing.xl),
            PrimaryButton(
              label: 'Enregistrer',
              loading: saving,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }
}
