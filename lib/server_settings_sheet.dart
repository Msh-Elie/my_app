import 'package:flutter/material.dart';

import 'api_client.dart';

const Color _accent = Color(0xFFFE6F0B);

/// Feuille de configuration de l'URL du backend.
/// Nécessaire pour tester sur téléphone physique : on y saisit l'adresse
/// IP Wi-Fi du PC qui héberge le serveur (ex: http://192.168.1.50:3002).
Future<void> showServerSettingsSheet(BuildContext context) async {
  final controller =
      TextEditingController(text: ApiClient.instance.baseUrl);

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
    backgroundColor: const Color(0xFF141414),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (sheetContext) {
      String? feedback;
      bool testing = false;

      return StatefulBuilder(
        builder: (context, setSheetState) {
          Future<void> saveAndTest() async {
            setSheetState(() {
              testing = true;
              feedback =
                  'Test en cours… si le serveur est en pause (plan gratuit), le réveil peut prendre jusqu\'à 50s.';
            });
            await ApiClient.instance.setBaseUrl(controller.text);
            String message;
            try {
              final resp = await ApiClient.instance
                  .getJson('/healthz', timeout: kColdStartTimeout);
              message = resp.statusCode == 200
                  ? '✅ Serveur joignable (${ApiClient.instance.baseUrl})'
                  : '⚠️ Serveur répond avec le code ${resp.statusCode}';
            } catch (_) {
              message =
                  '❌ Serveur injoignable à ${ApiClient.instance.baseUrl}';
            }
            setSheetState(() {
              testing = false;
              feedback = message;
            });
          }

          return Padding(
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 24,
              bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Serveur backend',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Sur téléphone physique, indiquez l\'adresse IP Wi-Fi du PC '
                  'qui héberge le backend (même réseau Wi-Fi requis).',
                  style: TextStyle(color: Colors.white60, fontSize: 13),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: controller,
                  keyboardType: TextInputType.url,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                  cursorColor: _accent,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFF1C1C1C),
                    labelText: 'URL du backend',
                    hintText: 'http://192.168.1.50:3002',
                    hintStyle: const TextStyle(color: Colors.white24),
                    labelStyle:
                        const TextStyle(color: Colors.white70, fontSize: 14),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0x44FE6F0B)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: _accent, width: 2),
                    ),
                  ),
                ),
                if (feedback != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    feedback!,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
                const SizedBox(height: 18),
                ElevatedButton(
                  onPressed: testing ? null : saveAndTest,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(26)),
                    textStyle: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  child: testing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.black),
                        )
                      : const Text('Enregistrer et tester'),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}
