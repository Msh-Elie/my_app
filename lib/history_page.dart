import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'api_client.dart';
import 'history_storage.dart';

class HistoryPage extends StatelessWidget {
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeChange;

  const HistoryPage({
    super.key,
    required this.themeMode,
    required this.onThemeChange,
  });

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF000000),
      body: SafeArea(
        child: HistoryContent(embedded: false),
      ),
    );
  }
}

class HistoryContent extends StatefulWidget {
  final bool embedded;

  const HistoryContent({super.key, required this.embedded});

  @override
  State<HistoryContent> createState() => _HistoryContentState();
}

class _HistoryContentState extends State<HistoryContent> {
  static const Color _accent = Color(0xFFFE6F0B);
  static const Color _surface = Color(0xFF000000);
  static const Color _card = Color(0xFF121212);

  int selectedStatus = 0; // 0 = tout, 1 = valide, 2 = en_cours, 3 = echec
  bool loading = true;

  List<HistoryRecord> persisted = const [];

  String _normalizeUiStatus(String? status, String? rawStatus) {
    final s = (status ?? '').trim().toLowerCase();
    final r = (rawStatus ?? '').trim().toUpperCase();

    if (s == 'valide') return 'valide';
    if (r == 'SUCCESS' || r == 'COMPLETED' || r == 'DUPLICATE_IGNORED') {
      return 'valide';
    }

    if (s == 'echec' || s == 'failed' || s == 'error') return 'echec';
    if (r == 'FAILED' || r == 'ERROR' || r == 'REJECTED' || r == 'CANCELLED') {
      return 'echec';
    }

    return 'en_cours';
  }

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final resp = await ApiClient.instance
          .getJson('/api/history?limit=80', timeout: kColdStartTimeout);

      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body);
        final rawItems = (decoded is Map<String, dynamic>) ? decoded['items'] : null;
        if (rawItems is List) {
          final fromApi = rawItems
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .map(
                (e) => HistoryRecord(
                  id: e['id']?.toString() ?? '',
                  from: e['from']?.toString() ?? '',
                  to: e['to']?.toString() ?? '',
                  amount: e['amount']?.toString() ?? '',
                  status: _normalizeUiStatus(
                    e['status']?.toString(),
                    e['rawStatus']?.toString(),
                  ),
                  date: e['date']?.toString() ?? '',
                  fromLogo: e['fromLogo']?.toString(),
                  toLogo: e['toLogo']?.toString(),
                ),
              )
              .toList();

          if (!mounted) return;
          setState(() {
            persisted = fromApi;
            loading = false;
          });
          return;
        }
      }
    } catch (_) {
      // backend unavailable: fallback to local history
    }

    final stored = await HistoryStorage.load();
    if (!mounted) return;
    setState(() {
      persisted = stored;
      loading = false;
    });
  }

  List<HistoryRecord> get _visibleEntries {
    if (selectedStatus == 0) return persisted;
    final wanted = switch (selectedStatus) {
      1 => 'valide',
      3 => 'echec',
      _ => 'en_cours',
    };
    return persisted.where((e) => e.status.toLowerCase() == wanted).toList();
  }

  @override
  Widget build(BuildContext context) {
    final visibleEntries = _visibleEntries;

    return Container(
      color: _surface,
      child: Column(
        children: [
          if (!widget.embedded)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left, color: Colors.white, size: 28),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Expanded(
                    child: Center(
                      child: Text(
                        'Historique',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 36,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
          if (!widget.embedded) Container(height: 1, color: const Color(0x22FFFFFF)),
          SizedBox(height: widget.embedded ? 30 : 36),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: widget.embedded ? 12 : 16),
            child: Row(
              children: [
                Expanded(
                  child: _StatusChip(
                    label: 'Tout',
                    active: selectedStatus == 0,
                    onTap: () => setState(() => selectedStatus = 0),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _StatusChip(
                    label: 'Valide',
                    active: selectedStatus == 1,
                    onTap: () => setState(() => selectedStatus = 1),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _StatusChip(
                    label: 'En cours',
                    active: selectedStatus == 2,
                    onTap: () => setState(() => selectedStatus = 2),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _StatusChip(
                    label: 'Échec',
                    active: selectedStatus == 3,
                    onTap: () => setState(() => selectedStatus = 3),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator(color: _accent))
                : visibleEntries.isEmpty
                    ? const Center(
                        child: Text(
                          'Aucune transaction pour ce filtre',
                          style: TextStyle(fontSize: 16, color: Color(0xFFB5B5B5)),
                        ),
                      )
                    : ListView.separated(
                        padding: EdgeInsets.fromLTRB(
                          widget.embedded ? 10 : 16,
                          8,
                          widget.embedded ? 10 : 16,
                          20,
                        ),
                        itemBuilder: (context, index) {
                          final item = visibleEntries[index];
                          return _HistoryCard(item: item, cardColor: _card, accent: _accent);
                        },
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemCount: visibleEntries.length,
                      ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _StatusChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.of(context).size.width < 390;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: EdgeInsets.all(compact ? 2 : 2.5),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1C),
          borderRadius: BorderRadius.circular(compact ? 12 : 16),
        ),
        child: Container(
          padding: EdgeInsets.symmetric(vertical: compact ? 8 : 10),
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C1C),
            borderRadius: BorderRadius.circular(compact ? 10 : 13),
            boxShadow: active
                ? const [
                    BoxShadow(
                      color: Color(0x33FE6F0B),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: compact ? 13 : 14,
                fontWeight: FontWeight.w600,
                color: active ? const Color(0xFFFFB179) : const Color(0xFFE0E0E0),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final HistoryRecord item;
  final Color cardColor;
  final Color accent;

  const _HistoryCard({
    required this.item,
    required this.cardColor,
    required this.accent,
  });

  Color _badgeColor(String label) {
    final key = label.toUpperCase();
    if (key.contains('USDT')) return const Color(0xFFFE6F0B);
    if (key.contains('MTN')) return const Color(0xFFF08D3A);
    if (key.contains('TRX')) return const Color(0xFFD95C00);
    if (key.contains('VOLET')) return const Color(0xFFFF8A2B);
    if (key.contains('DERIV')) return const Color(0xFFC24F00);
    if (key.contains('CELTIS')) return const Color(0xFF9D4300);
    return const Color(0xFFFE6F0B);
  }

  String _shortLabel(String label) {
    final clean = label.trim();
    if (clean.isEmpty) return '?';
    final parts = clean.split(' ');
    if (parts.length > 1 && parts.last.length == 2) {
      return parts.first.toUpperCase();
    }
    return clean.toUpperCase();
  }

  String? _logoAssetFor(String label) {
    final key = label.toUpperCase();
    if (key.contains('MTN')) return 'assets/logos/mtn.png';
    if (key.contains('AIRTEL')) return 'assets/logos/airtel.svg';
    if (key.contains('ORANGE') || key.contains('OM ')) return 'assets/logos/orange.png';
    if (key.contains('MOOV')) return 'assets/logos/moov.png';
    if (key.contains('CELTIS')) return 'assets/logos/celtis.png';
    if (key.contains('WAVE')) return 'assets/logos/wave.png';
    if (key.contains('VODAFONE')) return 'assets/logos/vodafone.png';
    if (key.contains('SAFARICOM')) return 'assets/logos/safaricom.png';
    return null;
  }

  bool get _isSuccess => item.status.toLowerCase() == 'valide';
  bool get _isFailure => item.status.toLowerCase() == 'echec';

  Color get _statusColor => _isSuccess
      ? const Color(0xFF33D17A)
      : _isFailure
          ? const Color(0xFFFF6B6B)
          : const Color(0xFFFFB06D);

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.of(context).size.width < 390;
    final fromLabel = _shortLabel(item.from);
    final toLabel = _shortLabel(item.to);
    final fromLogo = _logoAssetFor(item.from) ?? item.fromLogo;
    final toLogo = _logoAssetFor(item.to) ?? item.toLogo;
    final statusText = _isSuccess
        ? 'Succes'
        : _isFailure
            ? 'Échec'
            : 'En cours';

    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14, vertical: compact ? 10 : 14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(compact ? 14 : 18),
      ),
      child: Row(
        children: [
          _CoinBadge(label: fromLabel, color: _badgeColor(item.from), compact: compact, logoAsset: fromLogo),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: compact ? 3 : 6),
            child: Icon(Icons.arrow_right_alt_rounded, size: compact ? 19 : 24, color: const Color(0xFFFFA35B)),
          ),
          _CoinBadge(label: toLabel, color: _badgeColor(item.to), compact: compact, logoAsset: toLogo),
          SizedBox(width: compact ? 8 : 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ID : ${item.id}',
                  style: TextStyle(
                    fontSize: compact ? 15 : 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: compact ? 1 : 2),
                Text(
                  item.date,
                  style: TextStyle(fontSize: compact ? 12 : 15, color: const Color(0xFFB8B8B8)),
                ),
              ],
            ),
          ),
          SizedBox(
            width: compact ? 96 : 124,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  item.amount,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: compact ? 15 : 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: compact ? 1 : 2),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      statusText,
                      style: TextStyle(
                        fontSize: compact ? 12 : 15,
                        fontWeight: FontWeight.w500,
                        color: _statusColor,
                      ),
                    ),
                    SizedBox(width: compact ? 2 : 3),
                    Icon(
                      _isSuccess
                          ? Icons.check
                          : _isFailure
                              ? Icons.close
                              : Icons.schedule,
                      color: _statusColor,
                      size: compact ? 13 : 16,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CoinBadge extends StatelessWidget {
  final String label;
  final Color color;
  final bool compact;
  final String? logoAsset;

  const _CoinBadge({required this.label, required this.color, required this.compact, this.logoAsset});

  @override
  Widget build(BuildContext context) {
    final size = compact ? 36.0 : 46.0;
    final textStyle = TextStyle(
      fontSize: compact ? (label.length > 4 ? 8 : 10) : (label.length > 4 ? 10 : 12),
      fontWeight: FontWeight.w700,
      color: color.computeLuminance() > 0.7 ? Colors.black : Colors.white,
    );

    Widget badgeContent;
    if (logoAsset != null) {
      if (logoAsset!.startsWith('http://') || logoAsset!.startsWith('https://')) {
        badgeContent = ClipOval(
          child: Image.network(
            logoAsset!,
            width: compact ? 21 : 27,
            height: compact ? 21 : 27,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Text(label, textAlign: TextAlign.center, style: textStyle),
          ),
        );
      } else {
        if (logoAsset!.toLowerCase().endsWith('.svg')) {
          badgeContent = SvgPicture.asset(
            logoAsset!,
            width: compact ? 21 : 27,
            height: compact ? 21 : 27,
            fit: BoxFit.contain,
          );
        } else {
          badgeContent = Image.asset(
            logoAsset!,
            width: compact ? 21 : 27,
            height: compact ? 21 : 27,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Text(label, textAlign: TextAlign.center, style: textStyle),
          );
        }
      }
    } else {
      badgeContent = Text(label, textAlign: TextAlign.center, style: textStyle);
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: logoAsset != null ? const Color(0x00000000) : color,
        shape: BoxShape.circle,
        boxShadow: const [
          BoxShadow(color: Color(0x22000000), blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: Center(
        child: badgeContent,
      ),
    );
  }
}
