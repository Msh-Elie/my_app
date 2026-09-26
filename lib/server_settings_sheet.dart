import 'package:flutter/material.dart';

import 'api_client.dart';
import 'theme.dart';
import 'ui_kit.dart';

/// Feuille de configuration de l'URL du backend.
/// Nécessaire pour tester sur téléphone physique : on y saisit l'adresse
/// IP Wi-Fi du PC qui héberge le serveur (ex: http://192.168.1.50:3002).
Future<void> showServerSettingsSheet(BuildContext context) async {
  final controller = TextEditingController(text: ApiClient.instance.baseUrl);

  try {
    await _showSheet(context, controller);
  } finally {
    controller.dispose();
  }
}

Future<void> _showSheet(
    BuildContext context, TextEditingController controller) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) {
      String? feedback;
      Tone feedbackTone = Tone.neutral;
      bool testing = false;

      return StatefulBuilder(
        builder: (context, setSheetState) {
          Future<void> saveAndTest() async {
            setSheetState(() {
              testing = true;
              feedbackTone = Tone.neutral;
              feedback = 'Test en cours… si le serveur est en pause '
                  '(plan gratuit), le réveil peut prendre jusqu\'à 50 s.';
            });
            await ApiClient.instance.setBaseUrl(controller.text);

            String message;
            Tone tone;
            try {
              final resp = await ApiClient.instance
                  .getJson('/healthz', timeout: kColdStartTimeout);
              if (resp.statusCode == 200) {
                message = 'Serveur joignable (${ApiClient.instance.baseUrl})';
                tone = Tone.success;
              } else {
                message = 'Le serveur répond avec le code ${resp.statusCode}';
                tone = Tone.warning;
              }
            } catch (_) {
              message = 'Serveur injoignable à ${ApiClient.instance.baseUrl}';
              tone = Tone.danger;
            }

            setSheetState(() {
              testing = false;
              feedback = message;
              feedbackTone = tone;
            });
          }

          return Padding(
            padding: EdgeInsets.only(
              left: AppSpacing.xl,
              right: AppSpacing.xl,
              top: AppSpacing.sm,
              bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.xl,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const PageHeading(
                  title: 'Serveur backend',
                  subtitle: 'Sur téléphone physique, indiquez l\'adresse IP '
                      'Wi-Fi du PC qui héberge le backend (même réseau requis).',
                ),
                const SizedBox(height: AppSpacing.xl),
                TextField(
                  controller: controller,
                  keyboardType: TextInputType.url,
                  style: context.text.bodyLarge,
                  cursorColor: context.colors.brand,
                  decoration: const InputDecoration(
                    labelText: 'URL du backend',
                    hintText: 'http://192.168.1.50:3002',
                  ),
                ),
                if (feedback != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  InfoBanner(
                    message: feedback!,
                    tone: feedbackTone,
                    icon: switch (feedbackTone) {
                      Tone.success => Icons.check_circle_outline_rounded,
                      Tone.danger => Icons.error_outline_rounded,
                      Tone.warning => Icons.warning_amber_rounded,
                      _ => Icons.hourglass_empty_rounded,
                    },
                  ),
                ],
                const SizedBox(height: AppSpacing.xl),
                PrimaryButton(
                  label: 'Enregistrer et tester',
                  loading: testing,
                  onPressed: saveAndTest,
                ),
              ],
            ),
          );
        },
      );
    },
  );
}
