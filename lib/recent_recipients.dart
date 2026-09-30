import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Un bénéficiaire déjà servi, conservé pour être re-proposé.
class RecentRecipient {
  /// Partie locale du numéro, telle que saisie (sans indicatif).
  final String phone;

  /// Libellé de l'opérateur de destination (« MOOV BJ »).
  final String provider;

  /// Nom renvoyé par l'opérateur, quand il a pu être résolu.
  final String? name;

  const RecentRecipient({
    required this.phone,
    required this.provider,
    this.name,
  });

  Map<String, dynamic> toJson() =>
      {'phone': phone, 'provider': provider, 'name': name};

  factory RecentRecipient.fromJson(Map<String, dynamic> json) =>
      RecentRecipient(
        phone: json['phone']?.toString() ?? '',
        provider: json['provider']?.toString() ?? '',
        name: (json['name']?.toString().trim().isEmpty ?? true)
            ? null
            : json['name'].toString(),
      );

  /// Deux entrées désignent le même bénéficiaire si le numéro **et**
  /// l'opérateur coïncident : le même numéro chez deux réseaux n'est pas le
  /// même compte.
  bool sameAs(RecentRecipient other) =>
      phone == other.phone && provider == other.provider;

  /// Ce qu'on affiche sur la puce : le nom s'il est connu, sinon le numéro.
  String get display => name ?? phone;
}

/// Mémorise les derniers bénéficiaires, en local sur l'appareil.
///
/// Renvoyer de l'argent à quelqu'un est le geste le plus fréquent d'une
/// application de transfert ; retaper dix chiffres à chaque fois est le genre
/// de friction qu'on ne remarque qu'une fois disparue. Rien ne part au
/// serveur : ces numéros restent sur le téléphone de l'utilisateur.
abstract final class RecentRecipients {
  static const String _key = 'recent_recipients_v1';

  /// Au-delà, la liste cesse d'être une aide et devient un annuaire.
  static const int maxEntries = 8;

  static Future<List<RecentRecipient>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((e) => RecentRecipient.fromJson(Map<String, dynamic>.from(e)))
          .where((r) => r.phone.isNotEmpty && r.provider.isNotEmpty)
          .toList();
    } catch (_) {
      // Stockage illisible : on repart d'une liste vide plutôt que d'échouer.
      return const [];
    }
  }

  /// Ajoute (ou remonte) un bénéficiaire en tête de liste.
  static Future<void> remember(RecentRecipient recipient) async {
    if (recipient.phone.isEmpty || recipient.provider.isEmpty) return;
    try {
      final existing = await load();
      final next = <RecentRecipient>[
        recipient,
        ...existing.where((r) => !r.sameAs(recipient)),
      ].take(maxEntries).toList();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode(next.map((r) => r.toJson()).toList()),
      );
    } catch (_) {
      // Échec d'écriture : sans conséquence, le transfert a bien eu lieu.
    }
  }

  /// Les bénéficiaires joignables sur l'opérateur donné.
  static List<RecentRecipient> forProvider(
    List<RecentRecipient> all,
    String provider,
  ) =>
      all.where((r) => r.provider == provider).toList();

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }
}
