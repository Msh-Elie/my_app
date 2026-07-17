import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class HistoryRecord {
  final String id;
  final String from;
  final String to;
  final String amount;
  final String status;
  final String date;
  final String? fromLogo;
  final String? toLogo;

  const HistoryRecord({
    required this.id,
    required this.from,
    required this.to,
    required this.amount,
    required this.status,
    required this.date,
    this.fromLogo,
    this.toLogo,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'from': from,
      'to': to,
      'amount': amount,
      'status': status,
      'date': date,
      'fromLogo': fromLogo,
      'toLogo': toLogo,
    };
  }

  factory HistoryRecord.fromJson(Map<String, dynamic> json) {
    return HistoryRecord(
      id: json['id']?.toString() ?? '',
      from: json['from']?.toString() ?? '',
      to: json['to']?.toString() ?? '',
      amount: json['amount']?.toString() ?? '',
      status: json['status']?.toString() ?? 'valide',
      date: json['date']?.toString() ?? '',
      fromLogo: json['fromLogo']?.toString(),
      toLogo: json['toLogo']?.toString(),
    );
  }
}

class HistoryStorage {
  static const String _key = 'transfer_history_v1';
  static const int _maxEntries = 120;

  static Future<List<HistoryRecord>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((e) => HistoryRecord.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> prepend(HistoryRecord record) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await load();
    final next = <HistoryRecord>[record, ...current];
    if (next.length > _maxEntries) {
      next.removeRange(_maxEntries, next.length);
    }
    await prefs.setString(_key, jsonEncode(next.map((e) => e.toJson()).toList()));
  }

  /// Met à jour le statut d'une entrée existante (ex: quand le polling
  /// confirme un transfert initié en "en_cours").
  static Future<void> updateStatus(String id, String status) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await load();
    var changed = false;
    final next = current.map((record) {
      if (record.id != id || record.status == status) return record;
      changed = true;
      return HistoryRecord(
        id: record.id,
        from: record.from,
        to: record.to,
        amount: record.amount,
        status: status,
        date: record.date,
        fromLogo: record.fromLogo,
        toLogo: record.toLogo,
      );
    }).toList();
    if (!changed) return;
    await prefs.setString(_key, jsonEncode(next.map((e) => e.toJson()).toList()));
  }

  static String formatDisplayDate(DateTime dateTime) {
    final d = dateTime.day.toString().padLeft(2, '0');
    final m = dateTime.month.toString().padLeft(2, '0');
    final y = dateTime.year.toString();
    return '$d/$m/$y';
  }
}
