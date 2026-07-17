import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math';
import 'dart:async';
import 'package:uuid/uuid.dart';
import 'api_client.dart';
import 'history_page.dart';
import 'history_storage.dart';
import 'menu_page.dart';

// normalise une MSISDN PawaPay en supprimant le zéro national
// juste après l'indicatif pays, s'il est présent.
// ex : "2290151469075" → "22951469075"
String normalize(String msisdn) {
  // replaceFirstMapped lets us return the captured group directly
  return msisdn.replaceFirstMapped(RegExp(r'^(\d{3})0'), (m) => m[1] ?? '');
}

/// Compare un numéro saisi et un numéro prédit.
/// Si le numéro prédit ne diffère que par un zéro national
/// superflu, renvoie la version normalisée corrigée.
/// Renvoie `null` si les deux numéros sont incompatibles.
String? tryNormalizeCorrection(String sanitizedSender, String predictedNumber) {
  final ns = normalize(sanitizedSender);
  final np = normalize(predictedNumber);
  if (np == ns) return ns;
  if (np.endsWith(ns)) return np;
  return null;
}

// carte de conversion de code pays → devise utilisée par getCurrencyForProvider
const Map<String, String> countryCurrencies = {
  "BJ": "XOF", // Bénin - Franc CFA
  "BF": "XOF", // Burkina Faso - Franc CFA
  "CM": "XAF", // Cameroun - Franc CFA
  "CG": "XAF", // Congo - Franc CFA
  "CI": "XOF", // Côte d'Ivoire - Franc CFA
  "GH": "GHS", // Ghana - Cedi
  "GN": "GNF", // Guinée - Franc guinéen
  "KE": "KES", // Kenya - Shilling kényan
  "ML": "XOF", // Mali - Franc CFA
  "NE": "XOF", // Niger - Franc CFA
  "CD": "CDF", // République Démocratique du Congo - Franc congolais
  "SN": "XOF", // Sénégal - Franc CFA
  "TG": "XOF", // Togo - Franc CFA
  "GA": "XAF", // Gabon - Franc CFA
};

// helpers that were previously methods on the state class but are pure
// functions; moving them here makes them easier to call from tests.
String getCurrencyForProvider(String provider) {
  // Extraire le code pays (les deux derniers caractères)
  String countryCode = provider.length >= 2
      ? provider.substring(provider.length - 2)
      : "BJ"; // Valeur par défaut
  return countryCurrencies[countryCode] ?? "XOF"; // XOF par défaut
}

String normalizeProvider(String provider) {
  // Previously we attempted a naive transformation ("MTN BJ" ->
  // "MTN_BJ"), but the backend needs the *raw* provider name so it can
  // look up the correct PawaPay code.  If we send an underscored value
  // the server assumes it's already the final code and forwards it
  // unchanged, which causes the INVALID_PARAMETER error from PawaPay.
  //
  // Keep the original string; the server will perform any mapping it
  // deems necessary (using active-conf or a static map).
  return provider;
}

Set<String> _codeRange(int start, int end) {
  return {for (var i = start; i <= end; i++) i.toString().padLeft(2, '0')};
}

Set<String> _codeRangeWithWidth(int start, int end, int width) {
  return {for (var i = start; i <= end; i++) i.toString().padLeft(width, '0')};
}

final Map<String, Set<String>> beninOperatorCodes = {
  'MTN BJ': {
    '42', '46', '50', '51', '52', '53', '54', '56', '57', '59', '61', '62',
    '66', '67', '69', '90', '91', '96', '97'
  },
  'MOOV BJ': {
    '45', '55', '58', '60', '64', '68', '94', '95', '98', '99',
    ..._codeRange(63, 65),
  },
  'CELTIS BJ': {
    '28', '29', '92', '93',
    ..._codeRange(20, 24),
    ..._codeRange(40, 44),
    ..._codeRange(47, 49),
  },
};

final Map<String, Set<String>> operatorPrefixRules = {
  // Nigeria
  'MTN NG': {'0803', '0806', '0810', '0813', '0814', '0816', '0903', '0703'},
  'GLO NG': {'0805', '0811', '0705', '0905'},
  'AIRTEL NG': {'0802', '0808', '0812', '0708', '0902'},
  '9MOBILE NG': {'0809', '0817', '0818', '0909'},

  // Cote d'Ivoire — plan 2021 : 10 chiffres, 01 Moov / 05 MTN / 07 Orange
  'ORANGE CI': {'07'},
  'OM CI': {'07'},
  'MTN CI': {'05'},
  'MOOV CI': {'01'},

  // Ghana
  'MTN GH': {'024', '054', '055', '059'},
  'VODAFONE GH': {'020', '050'},
  'AIRTEL GH': {'027', '057'},

  // Senegal
  'ORANGE SN': {'76', '77', '78'},
  'OM SN': {'76', '77', '78'},
  'FREE SN': {'70', '75'},
  'EXPRESSO SN': {'72'},

  // South Africa
  'VODACOM ZA': {'082', '072', '079'},
  'MTN ZA': {'083', '073', '078'},
  'CELL C ZA': {'084', '074'},
  'TELKOM MOBILE ZA': {'081'},

  // Kenya
  'SAFARICOM KE': {
    ..._codeRangeWithWidth(700, 729, 3),
    ..._codeRangeWithWidth(740, 769, 3),
    ..._codeRangeWithWidth(790, 799, 3),
  },
  'AIRTEL KE': {
    ..._codeRangeWithWidth(730, 739, 3),
    ..._codeRangeWithWidth(780, 789, 3),
  },
  'TELKOM KE': {
    ..._codeRangeWithWidth(770, 779, 3),
  },

  // Mali
  'ORANGE ML': {'66', '67', '76', '77'},
  'OM ML': {'66', '67', '76', '77'},
  'MOOV ML': {'60', '61', '62', '63'},

  // Maroc (high-level ranges, provider differentiation may evolve)
  'IAM MA': {'06'},
  'MAROC TELECOM MA': {'06'},
  'ORANGE MA': {'06'},
  'INWI MA': {'06'},
};

final Map<String, List<int>> countryLocalLengthRules = {
  'NG': [10, 11],
  'BJ': [10, 10],
  'BF': [8, 8],
  'CM': [9, 9],
  'CG': [9, 9],
  'CI': [10, 10],
  'GH': [10, 10],
  'GN': [9, 9],
  'KE': [10, 10],
  'ML': [8, 8],
  'MA': [9, 10],
  'NE': [8, 8],
  'CD': [9, 10],
  'SN': [9, 9],
  'TG': [8, 8],
  'GA': [8, 8],
  'ZA': [9, 10],
};

String digitsOnly(String value) => value.replaceAll(RegExp(r'[^0-9]'), '');

String countryCodeFromProvider(String provider) {
  return provider.length >= 2 ? provider.substring(provider.length - 2) : 'BJ';
}

bool _matchesAnyPrefix(String digits, Set<String> prefixes) {
  final normalized = digits.startsWith('0') && digits.length > 1
      ? digits.substring(1)
      : digits;
  for (final prefix in prefixes) {
    final plainPrefix = prefix.startsWith('0') && prefix.length > 1
        ? prefix.substring(1)
        : prefix;
    if (digits.startsWith(prefix) || normalized.startsWith(prefix)) {
      return true;
    }
    if (digits.startsWith(plainPrefix) || normalized.startsWith(plainPrefix)) {
      return true;
    }
  }
  return false;
}

String numberHintForProvider(String provider) {
  if (provider.endsWith('BJ')) {
    return 'Format attendu : 01XXXXXXXX (10 chiffres)';
  }
  final countryCode = countryCodeFromProvider(provider);
  final limits = countryLocalLengthRules[countryCode] ?? const [8, 10];
  final minLen = limits[0];
  final maxLen = limits[1];
  final prefixes = operatorPrefixRules[provider];
  if (prefixes != null && prefixes.isNotEmpty) {
    final sorted = prefixes.toList()..sort();
    if (sorted.length <= 8) {
      return 'Préfixes attendus: ${sorted.join(', ')}';
    }
    final preview = sorted.take(6).join(', ');
    return 'Préfixes attendus: $preview… (+${sorted.length - 6} autres)';
  }
  if (minLen == maxLen) {
    return 'Numéro local attendu : $minLen chiffres';
  }
  return 'Numéro local attendu : entre $minLen et $maxLen chiffres';
}

/// Erreurs bloquantes uniquement : longueur du numéro et format national.
/// La cohérence préfixe/opérateur n'est plus bloquante (voir
/// [prefixWarningForProvider]) : les plans de numérotation évoluent et la
/// vérité vient de PawaPay (predict-provider) au moment de l'envoi.
String? validateLocalNumberForProvider(String provider, String input) {
  final digits = digitsOnly(input);

  if (digits.isEmpty) {
    return 'Numéro requis';
  }

  if (provider.endsWith('BJ')) {
    if (digits.length != 10) {
      return 'Au Bénin, saisissez 10 chiffres (format 01XXXXXXXX)';
    }
    if (!digits.startsWith('01')) {
      return 'Le numéro béninois doit commencer par 01';
    }
    return null;
  }

  final countryCode = countryCodeFromProvider(provider);
  final limits = countryLocalLengthRules[countryCode] ?? const [8, 10];
  final minLen = limits[0];
  final maxLen = limits[1];

  if (digits.length < minLen || digits.length > maxLen) {
    if (minLen == maxLen) {
      return 'Le numéro local doit contenir exactement $minLen chiffres';
    }
    return 'Le numéro local doit contenir entre $minLen et $maxLen chiffres';
  }

  return null;
}

/// Avertissement non bloquant si le préfixe saisi ne correspond pas aux
/// tables locales de l'opérateur. N'empêche jamais l'envoi.
String? prefixWarningForProvider(String provider, String input) {
  final digits = digitsOnly(input);
  if (digits.isEmpty) return null;

  if (provider.endsWith('BJ')) {
    final allowedCodes = beninOperatorCodes[provider];
    if (allowedCodes != null && digits.length >= 4 && digits.startsWith('01')) {
      final operatorCode = digits.substring(2, 4);
      if (!allowedCodes.contains(operatorCode)) {
        return 'Préfixe 01$operatorCode inhabituel pour $provider — vérifiez le numéro';
      }
    }
    return null;
  }

  final allowedPrefixes = operatorPrefixRules[provider];
  if (allowedPrefixes != null && allowedPrefixes.isNotEmpty) {
    if (!_matchesAnyPrefix(digits, allowedPrefixes)) {
      final sorted = allowedPrefixes.toList()..sort();
      return 'Préfixe inhabituel pour $provider (attendu: ${sorted.join(', ')})';
    }
  }

  return null;
}

class HomePage extends StatefulWidget {
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeChange;
  final VoidCallback? onLoggedOut;

  const HomePage({
    super.key,
    required this.themeMode,
    required this.onThemeChange,
    this.onLoggedOut,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _OperatorSelectionSession {
  static const String defaultProvider = 'MTN BJ';
  static String selectedFrom = defaultProvider;
  static String selectedTo = defaultProvider;
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
int selectedTab = 0;
late TabController tabController;

// progress indicator at bottom
bool inProgress = false;
String progressText = '';
Timer? recipientLookupDebounce;
Timer? statusPollTimer;
bool recipientLookupInFlight = false;
bool recipientNameResolved = false;
String? resolvedRecipientName;
String? recipientLookupMessage;
int recipientLookupVersion = 0;

void _setProgress(String text) {
  setState(() {
    inProgress = text.isNotEmpty;
    progressText = text;
  });
}

// Liste de secours si le serveur est injoignable au démarrage. La liste
// réelle est chargée depuis /api/providers (source : PawaPay active-conf),
// avec les codes exacts — voir _loadProviders().
List<String> providers = [
"MTN BJ", "MOOV BJ", "MOOV BF", "OM BF",
"MTN CM", "OM CM", "MTN CG", "MTN CI", "MOOV CI",
"OM CI", "WAVE CI", "MTN GH", "VODAFONE GH", "AIRTEL GH",
"MTN GN", "OM GN", "AIRTEL KE", "SAFARICOM KE", "OM ML",
"MOOV ML", "AIRTEL NE", "OM NE", "AIRTEL CD", "OM CD",
"M-PESA CD", "OM SN", "WAVE SN", "YAS TG", "TOGO TG",
"MOOV GA", "AIRTEL GA"
];

Map<String, String> providerPrefixes = {
"MTN BJ": "+229", "MOOV BJ": "+229",
"MOOV BF": "+226", "OM BF": "+226", "MTN CM": "+237",
"OM CM": "+237", "MTN CG": "+242", "MTN CI": "+225",
"MOOV CI": "+225", "OM CI": "+225", "WAVE CI": "+225",
"MTN GH": "+233", "VODAFONE GH": "+233", "AIRTEL GH": "+233",
"MTN GN": "+224", "OM GN": "+224", "AIRTEL KE": "+254",
"SAFARICOM KE": "+254", "OM ML": "+223", "MOOV ML": "+223",
"AIRTEL NE": "+227", "OM NE": "+227", "AIRTEL CD": "+243",
"OM CD": "+243", "M-PESA CD": "+243", "OM SN": "+221",
"WAVE SN": "+221", "YAS TG": "+228", "TOGO TG": "+228",
"MOOV GA": "+241", "AIRTEL GA": "+241",
};

// libellé -> code PawaPay exact (rempli par /api/providers)
Map<String, String> providerCodes = {};

/// Charge la liste des opérateurs réellement disponibles chez PawaPay.
/// En cas d'échec (hors-ligne), la liste statique ci-dessus reste utilisée.
Future<void> _loadProviders() async {
  try {
    final resp = await ApiClient.instance
        .getJson('/api/providers', timeout: kColdStartTimeout);
    if (resp.statusCode != 200) return;
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final list = (data['providers'] as List?)?.whereType<Map>().toList() ?? [];
    if (list.isEmpty) return;

    final newProviders = <String>[];
    final newPrefixes = <String, String>{};
    final newCodes = <String, String>{};
    for (final p in list) {
      final label = p['label']?.toString() ?? '';
      final code = p['code']?.toString() ?? '';
      final prefix = p['prefix']?.toString() ?? '';
      if (label.isEmpty || code.isEmpty || prefix.isEmpty) continue;
      newProviders.add(label);
      newPrefixes[label] = prefix;
      newCodes[label] = code;
    }
    if (newProviders.isEmpty || !mounted) return;

    setState(() {
      providers = newProviders;
      providerPrefixes = newPrefixes;
      providerCodes = newCodes;
      if (!providers.contains(selectedFrom)) selectedFrom = providers.first;
      if (!providers.contains(selectedTo)) selectedTo = providers.first;
      _rememberOperatorSelection();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncOperatorWheelPositions();
    });
  } catch (_) {
    // serveur injoignable : on garde la liste statique
  }
}

String selectedFrom = _OperatorSelectionSession.defaultProvider;
String selectedTo = _OperatorSelectionSession.defaultProvider;

late FixedExtentScrollController fromController;
late FixedExtentScrollController toController;
late TextEditingController sendController;
late TextEditingController receiveController;
late TextEditingController amountController;

int stepIndex = 0;

String? lastOperationStatus;
String? lastOperationTxId;
String? lastOperationAmount;
String? lastOperationCurrency;
String? lastOperationMessage;
String? lastOperationDate;
String? lastOperationFrom;
String? lastOperationTo;
String? lastOperationReceiver;

String _resolvedSessionProvider(String provider) {
  return providers.contains(provider)
      ? provider
      : _OperatorSelectionSession.defaultProvider;
}

void _rememberOperatorSelection() {
  _OperatorSelectionSession.selectedFrom = selectedFrom;
  _OperatorSelectionSession.selectedTo = selectedTo;
}

void _syncOperatorWheelPositions() {
  try {
    final fromIndex = providers.indexOf(selectedFrom);
    if (fromIndex >= 0 && fromController.hasClients) {
      fromController.jumpToItem(fromIndex);
    }
    final toIndex = providers.indexOf(selectedTo);
    if (toIndex >= 0 && toController.hasClients) {
      toController.jumpToItem(toIndex);
    }
  } catch (_) {}
}

@override
void initState() {
super.initState();

selectedFrom = _resolvedSessionProvider(_OperatorSelectionSession.selectedFrom);
selectedTo = _resolvedSessionProvider(_OperatorSelectionSession.selectedTo);

// liste des opérateurs réellement disponibles (PawaPay active-conf)
_loadProviders();

tabController = TabController(length: 2, vsync: this);
tabController.addListener(() {
setState(() {
selectedTab = tabController.index;
});
});

fromController = FixedExtentScrollController(initialItem: providers.indexOf(selectedFrom));
toController = FixedExtentScrollController(initialItem: providers.indexOf(selectedTo));

sendController = TextEditingController();
receiveController = TextEditingController();
amountController = TextEditingController();

WidgetsBinding.instance.addPostFrameCallback((_) {
  if (!mounted) return;
  _syncOperatorWheelPositions();
});
}

@override
void dispose() {
recipientLookupDebounce?.cancel();
statusPollTimer?.cancel();
fromController.dispose();
toController.dispose();
sendController.dispose();
receiveController.dispose();
amountController.dispose();
tabController.dispose();
super.dispose();
}

double computeFee(double amount) {
  if (amount <= 0) return 0;
  if (amount <= 1000) return 50;
  if (amount <= 5000) return 100;
  if (amount <= 10000) return 200;
  if (amount <= 15000) return 300;
  if (amount <= 20000) return 400;
  if (amount <= 25000) return 500;
  if (amount <= 50000) return 1000;
  if (amount <= 75000) return 1500;
  if (amount <= 100000) return 2000;
  if (amount <= 150000) return 2500;
  if (amount <= 200000) return 3000;
  if (amount <= 300000) return 4000;
  return 5000;
}

double get enteredAmount => double.tryParse(amountController.text.trim()) ?? 0;

double get transferFee => computeFee(enteredAmount);

double get payoutAmount {
  final payout = enteredAmount - transferFee;
  return payout > 0 ? payout : 0;
}

String get transferCurrency => getCurrencyForProvider(selectedFrom);

String _buildAutoReceiverName() {
  final digits = digitsOnly(receiveController.text);
  if (digits.isEmpty) return 'Beneficiaire en attente';
  final networkLabel = selectedTo.split(' ').first;
  final signature = digits.length <= 4 ? digits : digits.substring(digits.length - 4);
  return 'Compte $networkLabel • $signature';
}

String _formatPhonePreview(String provider, String input) {
  final digits = digitsOnly(input);
  if (digits.isEmpty) {
    return providerPrefixes[provider] ?? '';
  }
  final grouped = digits.replaceAllMapped(RegExp(r'.{1,2}'), (m) => '${m.group(0)} ').trimRight();
  return '${providerPrefixes[provider] ?? ''} $grouped'.trim();
}

String get resolvedRecipientDisplayName {
  final value = resolvedRecipientName?.trim();
  if (value != null && value.isNotEmpty) {
    return _formatRecipientDisplayName(value);
  }
  return _buildAutoReceiverName();
}

String _toTitleCaseWord(String word) {
  if (word.isEmpty) return word;
  if (word.toUpperCase() == word && word.length <= 3) return word;
  final lower = word.toLowerCase();
  return '${lower[0].toUpperCase()}${lower.substring(1)}';
}

String _formatRecipientDisplayName(String raw) {
  final cleaned = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (cleaned.isEmpty) return raw;

  final parts = cleaned.split(' ');
  if (parts.length < 2) {
    return _toTitleCaseWord(parts.first);
  }

  final surname = parts.first.toUpperCase();
  final given = parts.skip(1).map(_toTitleCaseWord).join(' ');
  return '$surname $given';
}

void _resetRecipientLookup({bool clearMessage = true}) {
  recipientLookupDebounce?.cancel();
  recipientLookupInFlight = false;
  recipientNameResolved = false;
  resolvedRecipientName = null;
  if (clearMessage) {
    recipientLookupMessage = null;
  }
}

Future<void> _lookupRecipientIdentity() async {
  final digits = digitsOnly(receiveController.text);
  final validation = validateLocalNumberForProvider(selectedTo, digits);
  if (digits.isEmpty || validation != null) {
    if (!mounted) return;
    setState(() {
      _resetRecipientLookup();
    });
    return;
  }

  final currentVersion = ++recipientLookupVersion;
  final msisdn = ((providerPrefixes[selectedTo] ?? '+') + digits).replaceFirst('+', '');

  if (mounted) {
    setState(() {
      recipientLookupInFlight = true;
      recipientLookupMessage = 'identification en cours';
    });
  }

  try {
    final response = await ApiClient.instance.postJson(
      '/api/resolve-recipient',
      {
        'phoneNumber': msisdn,
        'provider': selectedTo,
      },
      timeout: kColdStartTimeout,
    );

    final data = response.body.isNotEmpty
        ? jsonDecode(response.body) as Map<String, dynamic>
        : <String, dynamic>{};
    if (!mounted || currentVersion != recipientLookupVersion) return;

    final displayName = (data['displayName'] as String?)?.trim();
    final resolved = data['resolved'] == true;
    final source = data['source'] as String?;

    setState(() {
      recipientLookupInFlight = false;
      recipientNameResolved = resolved && displayName != null && displayName.isNotEmpty;
      resolvedRecipientName = displayName != null && displayName.isNotEmpty ? displayName : null;
      if (recipientNameResolved) {
        recipientLookupMessage = 'destinataire: $displayName';
      } else if (source == 'derived' && displayName != null && displayName.isNotEmpty) {
        recipientLookupMessage = 'identite auto: $displayName';
      } else {
        recipientLookupMessage = 'identite automatique utilisee';
      }
    });
  } on TimeoutException {
    if (!mounted || currentVersion != recipientLookupVersion) return;
    setState(() {
      recipientLookupInFlight = false;
      recipientNameResolved = false;
      resolvedRecipientName = null;
      recipientLookupMessage = 'identite automatique utilisee';
    });
  } catch (_) {
    if (!mounted || currentVersion != recipientLookupVersion) return;
    setState(() {
      recipientLookupInFlight = false;
      recipientNameResolved = false;
      resolvedRecipientName = null;
      recipientLookupMessage = 'identite automatique utilisee';
    });
  }
}

void _scheduleRecipientLookup() {
  recipientLookupDebounce?.cancel();
  final digits = digitsOnly(receiveController.text);
  final validation = validateLocalNumberForProvider(selectedTo, digits);
  if (digits.isEmpty || validation != null) {
    setState(() {
      _resetRecipientLookup();
    });
    return;
  }

  recipientLookupDebounce = Timer(const Duration(milliseconds: 500), () {
    _lookupRecipientIdentity();
  });
}

String get continueLabel {
  if (stepIndex == 4) return 'Nouveau transfert';
  if (stepIndex == 3) return 'Confirmer le transfert';
  if (stepIndex == 2) return 'Voir le recapitulatif';
  return 'Continuer';
}


bool get isContinueActive {
if (stepIndex == 0) {
return selectedFrom.isNotEmpty && selectedTo.isNotEmpty;
} else if (stepIndex == 1) {
return sendController.text.trim().isNotEmpty &&
  receiveController.text.trim().isNotEmpty;
} else if (stepIndex == 2) {
return amountController.text.trim().isNotEmpty;
} else if (stepIndex == 4) {
return true;
} else {
return amountController.text.trim().isNotEmpty;
}
}

void _captureOperationResult({
  required String status,
  required String txId,
  required String amount,
  required String currency,
  required String message,
}) {
  lastOperationStatus = status;
  lastOperationTxId = txId;
  lastOperationAmount = amount;
  lastOperationCurrency = currency;
  lastOperationMessage = message;
  lastOperationDate = HistoryStorage.formatDisplayDate(DateTime.now());
  lastOperationFrom = selectedFrom;
  lastOperationTo = selectedTo;
  final receiverPhonePreview = _formatPhonePreview(selectedTo, receiveController.text);
  lastOperationReceiver = recipientNameResolved
      ? '$resolvedRecipientDisplayName • $receiverPhonePreview'
      : receiverPhonePreview;
}

/// Interroge le backend toutes les 3 s jusqu'à ce que PawaPay confirme
/// (ou rejette) le dépôt, puis met à jour l'écran de résultat et
/// l'historique local. S'arrête après ~1 min si aucun statut définitif.
void _startStatusPolling(String depositId) {
  statusPollTimer?.cancel();
  int attempts = 0;
  const maxAttempts = 20;

  statusPollTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
    attempts++;
    if (attempts > maxAttempts) {
      timer.cancel();
      return;
    }
    try {
      final resp = await ApiClient.instance
          .getJson('/api/transfer-status/$depositId',
              timeout: const Duration(seconds: 8));
      if (resp.statusCode != 200) {
        if (resp.statusCode == 404 || resp.statusCode == 403) timer.cancel();
        return;
      }
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final uiStatus = (data['uiStatus'] ?? '').toString();
      if (uiStatus != 'valide' && uiStatus != 'echec') return;

      timer.cancel();
      await HistoryStorage.updateStatus(depositId, uiStatus);
      if (!mounted || lastOperationTxId != depositId) return;
      setState(() {
        lastOperationStatus = uiStatus;
        lastOperationMessage = uiStatus == 'valide'
            ? 'Le transfert a été confirmé par l\'opérateur.'
            : 'Le transfert a échoué (statut ${data['status'] ?? 'FAILED'}). Aucun montant ne sera prélevé.';
      });
    } catch (_) {
      // erreur réseau passagère : on retentera au prochain tick
    }
  });
}

void _resetTransferFlow() {
  statusPollTimer?.cancel();
  setState(() {
    stepIndex = 0;
    amountController.clear();
    sendController.clear();
    receiveController.clear();
    _resetRecipientLookup();
    lastOperationStatus = null;
    lastOperationTxId = null;
    lastOperationAmount = null;
    lastOperationCurrency = null;
    lastOperationMessage = null;
    lastOperationDate = null;
    lastOperationFrom = null;
    lastOperationTo = null;
    lastOperationReceiver = null;
  });
}

String? get sendNumberError {
  if (stepIndex != 1 || sendController.text.trim().isEmpty) return null;
  return validateLocalNumberForProvider(selectedFrom, sendController.text);
}

String? get sendNumberWarning {
  if (stepIndex != 1 || sendController.text.trim().isEmpty) return null;
  if (sendNumberError != null) return null;
  return prefixWarningForProvider(selectedFrom, sendController.text);
}

String? get sendNumberSuccess {
  if (stepIndex != 1 || sendController.text.trim().isEmpty) return null;
  if (sendNumberError != null || sendNumberWarning != null) return null;
  return 'Numero correct pour $selectedFrom';
}

String? get receiveNumberError {
  if (stepIndex != 1 || receiveController.text.trim().isEmpty) return null;
  return validateLocalNumberForProvider(selectedTo, receiveController.text);
}

String? get receiveNumberWarning {
  if (stepIndex != 1 || receiveController.text.trim().isEmpty) return null;
  if (receiveNumberError != null) return null;
  return prefixWarningForProvider(selectedTo, receiveController.text);
}

String? get receiveNumberSuccess {
  if (stepIndex != 1 || receiveController.text.trim().isEmpty) return null;
  if (receiveNumberError != null || receiveNumberWarning != null) return null;
  return 'Numero correct pour $selectedTo';
}

@override
Widget build(BuildContext context) {
const double spacingTitleToContent = 0;

return Scaffold(
backgroundColor: Colors.black,
resizeToAvoidBottomInset: false,
bottomNavigationBar: inProgress ? Container(
  color: Colors.grey[900],
  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  child: Row(
    children: [
      Expanded(
        child: Text(progressText, style: const TextStyle(color: Colors.white)),
      ),
      SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange),
      ),
    ],
  ),
) : null,
body: SafeArea(
child: Column(
  children: [
    Padding(
      padding: const EdgeInsets.only(top: 8, right: 16),
      child: Align(
        alignment: Alignment.topRight,
        child: IconButton(
          icon: const Icon(Icons.account_circle_outlined, size: 28, color: Colors.white),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => MenuPage(
                  themeMode: widget.themeMode,
                  onThemeChanged: widget.onThemeChange,
                  onLoggedOut: widget.onLoggedOut,
                ),
              ),
            );
          },
        ),
      ),
    ),
    const SizedBox(height: 20),

    Center(child: buildCustomTabBar()),
    const SizedBox(height: 20),

    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (selectedTab == 0 && stepIndex > 0 && stepIndex < 4) Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              icon: const Icon(
                Icons.chevron_left,
                size: 22,
                color: Colors.white,
              ),
              onPressed: () {
                if (stepIndex > 0) {
                  final newStep = stepIndex - 1;
                  if (newStep == 0) {
                    // Les roues sont hors du tree (step > 0) donc les controllers
                    // n'ont aucune position attachée : on peut les recréer
                    // avec le bon initialItem avant le rebuild.
                    final fi = providers.indexOf(selectedFrom).clamp(0, providers.length - 1);
                    final ti = providers.indexOf(selectedTo).clamp(0, providers.length - 1);
                    fromController.dispose();
                    toController.dispose();
                    fromController = FixedExtentScrollController(initialItem: fi);
                    toController = FixedExtentScrollController(initialItem: ti);
                  }
                  setState(() { stepIndex = newStep; });
                }
              },
            ),
          ),
          Center(
            child: Text(
              selectedTab == 0 ? "Transfert" : "Historique",
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    ),

    SizedBox(height: spacingTitleToContent),

    Expanded(
      child: selectedTab == 0
          ? LayoutBuilder(
              builder: (context, constraints) {
                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 420),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder: (child, animation) {
                    final offset = Tween<Offset>(
                      begin: const Offset(1.0, 0),
                      end: Offset.zero,
                    ).animate(animation);
                    return SlideTransition(position: offset, child: child);
                  },
                  child: SizedBox(
                    key: ValueKey(stepIndex),
                    width: double.infinity,
                    child: Transform.translate(
                      offset: const Offset(0, -8),
                      child: _buildStepContent(),
                    ),
                  ),
                );
              },
            )
          : const HistoryContent(embedded: true),
    ),

    if (selectedTab == 0 && stepIndex < 3) ...[
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          RichText(
            text: TextSpan(
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
              children: [
                TextSpan(text: selectedFrom),
                WidgetSpan(
                  child: Baseline(
                    baseline: 18,
                    baselineType: TextBaseline.alphabetic,
                    child: Text(
                      "→",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFFE6F0B),
                      ),
                    ),
                  ),
                ),
                TextSpan(text: selectedTo),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 22),
    ],

    if (selectedTab == 0)
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: isContinueActive
              ? (stepIndex >= 3 ? const Color(0xFFFE6F0B) : Colors.white)
                : Colors.grey,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 70, vertical: 16),
            minimumSize: const Size(280, 30),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30)),
            textStyle: const TextStyle(
                fontSize: 20, fontWeight: FontWeight.bold),
          ),
          onPressed: isContinueActive
? () {
if (stepIndex == 4) {
  _resetTransferFlow();
  return;
}
_onContinuePressed(
  context: context,
  stepIndex: stepIndex,
  setStepIndex: (i) => setState(() => stepIndex = i),
  amountController: amountController,
  sendController: sendController,
  receiveController: receiveController,
  selectedFrom: selectedFrom,
  selectedTo: selectedTo,
);
}
: null,

          child: Text(continueLabel),
        ),
      ),
    if (selectedTab == 0) const SizedBox(height: 20),

    if (selectedTab == 0 && stepIndex < 3)
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        width: double.infinity,
        color: Colors.black,
        child: const Text(
          "By continuing, you agree to our Terms of Use and have read and agreed to our Privacy Policy",
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white, fontSize: 12),
        ),
      ),
  ],
),
),
);
}

Widget _buildStepContent() {
if (stepIndex == 4) {
return _buildOperationResultStep();
}
if (stepIndex == 3) {
return _buildConfirmationStep();
}

if (stepIndex == 2) {
final frais = transferFee;
final net = payoutAmount;

// Obtenir les devises pour les providers sélectionnés
String fromCurrency = transferCurrency;

// Pour l'instant, on utilise la devise du pays d'origine
String displayCurrency = fromCurrency;

const double fieldWidth = 300;
const double horizontalPadding = 12;

return SizedBox(
key: const ValueKey('montant'),
height: 180,
child: Column(
  mainAxisAlignment: MainAxisAlignment.center,
  children: [
    // Champ centré avec devise dynamique
    Center(
      child: SizedBox(
        width: fieldWidth,
        child: TextField(
          controller: amountController,
          keyboardType: TextInputType.number,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
          decoration: InputDecoration(
            labelText: "Montant",
            labelStyle: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w500,
            ),
            suffixText: displayCurrency, // Devise dynamique
            suffixStyle: const TextStyle(
              color: Color(0xFFFE6F0B),
              fontWeight: FontWeight.bold,
            ),
            filled: true,
            fillColor: const Color(0xFF1C1C1C),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFFE6F0B)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFFE6F0B)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFFE6F0B), width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: horizontalPadding),
          ),
          onChanged: (_) => setState(() {}),
        ),
      ),
    ),
    const SizedBox(height: 12),
    // Textes alignés à gauche du champ avec devise dynamique
    if (amountController.text.trim().isNotEmpty) ...[
      Padding(
        padding: const EdgeInsets.only(left: horizontalPadding),
        child: SizedBox(
          width: fieldWidth,
          child: Text(
            "Frais : ${frais.toStringAsFixed(0)} $displayCurrency",
            style: const TextStyle(
              color: Colors.grey,
              fontSize: 12,
            ),
          ),
        ),
      ),
      const SizedBox(height: 4),
      Padding(
        padding: const EdgeInsets.only(left: horizontalPadding),
        child: SizedBox(
          width: fieldWidth,
          child: Text(
            "Montant net : ${net.toStringAsFixed(0)} $displayCurrency",
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    ],
  ],
),
);
}

return stepIndex == 0
? SizedBox(
key: const ValueKey('wheels'),
height: 200,
child: buildWheels(
fromController,
toController,
selectedFrom,
selectedTo,
    (from) => setState(() {
      selectedFrom = from;
      _rememberOperatorSelection();
    }),
    (to) => setState(() {
      selectedTo = to;
      _rememberOperatorSelection();
      _resetRecipientLookup();
    }),
),
)
: SizedBox(
key: const ValueKey('inputs'),
height: 270,
child: Column(
mainAxisAlignment: MainAxisAlignment.center,
children: [
  SizedBox(
    width: 300,
    child: CustomInputFieldWithFixedPrefix(
      label: "Numéro d'envoi",
      prefix: providerPrefixes[selectedFrom] ?? "+XXX",
      controller: sendController,
      errorText: sendNumberError,
      helperText: sendNumberWarning ??
          sendNumberSuccess ??
          numberHintForProvider(selectedFrom),
      helperIsSuccess: sendNumberSuccess != null,
      helperIsWarning: sendNumberWarning != null,
      maxLength: selectedFrom.endsWith('BJ') ? 10 : 10,
      onChanged: (_) => setState(() {}),
    ),
  ),
  const SizedBox(height: 30),
  SizedBox(
    width: 300,
    child: CustomInputFieldWithFixedPrefix(
      label: "Numéro de réception",
      prefix: providerPrefixes[selectedTo] ?? "+XXX",
      controller: receiveController,
      errorText: receiveNumberError,
      // le résultat du lookup (nom du bénéficiaire) prime sur le message générique
      helperText: recipientLookupMessage ??
          receiveNumberWarning ??
          receiveNumberSuccess ??
          numberHintForProvider(selectedTo),
      helperIsSuccess: recipientNameResolved ||
          (recipientLookupMessage == null && receiveNumberSuccess != null),
      helperIsWarning:
          recipientLookupMessage == null && receiveNumberWarning != null,
      maxLength: selectedTo.endsWith('BJ') ? 10 : 10,
      onChanged: (_) {
        setState(() {});
        _scheduleRecipientLookup();
      },
    ),
  ),
],
),
);
}

Widget _buildConfirmationStep() {
final amount = enteredAmount;
final fee = transferFee;
final payout = payoutAmount;
final currency = transferCurrency;
final receiverPhone = _formatPhonePreview(selectedTo, receiveController.text);
final senderPhone = _formatPhonePreview(selectedFrom, sendController.text);

return SingleChildScrollView(
  key: const ValueKey('confirmation'),
  padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
  child: Column(
    children: [
      Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 560),
        padding: const EdgeInsets.all(1.2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          gradient: const LinearGradient(
            colors: [Color(0xFFFE6F0B), Color(0x66FE6F0B), Color(0x22FFFFFF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33FE6F0B),
              blurRadius: 28,
              spreadRadius: 2,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0B0B0B),
            borderRadius: BorderRadius.circular(29),
          ),
          child: Stack(
            children: [
              Positioned(
                top: -20,
                right: -10,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [Color(0x44FE6F0B), Color(0x00FE6F0B)],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: const Color(0x22FE6F0B),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(Icons.verified_user_outlined, color: Color(0xFFFE6F0B)),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Confirmation finale',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Verifie les informations avant d\'envoyer le transfert.',
                                style: TextStyle(
                                  color: Colors.white60,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: const Color(0x14FFFFFF),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0x22FFFFFF)),
                      ),
                      child: Column(
                        children: [
                          // Identité du bénéficiaire mise en avant (façon MTN MoMo)
                          Container(
                            width: 54,
                            height: 54,
                            decoration: const BoxDecoration(
                              color: Color(0x22FE6F0B),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.person,
                                color: Color(0xFFFE6F0B), size: 30),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            resolvedRecipientDisplayName,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            receiverPhone,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 13),
                          ),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: recipientNameResolved
                                  ? const Color(0x2233D17A)
                                  : const Color(0x22FFB74D),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              recipientNameResolved
                                  ? 'Nom vérifié'
                                  : 'Identité non confirmée',
                              style: TextStyle(
                                color: recipientNameResolved
                                    ? const Color(0xFF33D17A)
                                    : const Color(0xFFFFB74D),
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child:
                                Divider(color: Color(0x22FFFFFF), height: 1),
                          ),
                          _buildConfirmationRow('Reseau', selectedTo, compact: true, allowWrap: true),
                          _buildConfirmationRow('Expediteur', senderPhone, compact: true, allowWrap: true),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF121212),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const Text(
                                'Montant qui sera debourse',
                                style: TextStyle(color: Colors.white70, fontSize: 13),
                              ),
                              const Spacer(),
                              Text(
                                '${amount.toStringAsFixed(0)} $currency',
                                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          _buildConfirmationRow('Frais', '${fee.toStringAsFixed(0)} $currency'),
                          _buildConfirmationRow('Montant net', '${payout.toStringAsFixed(0)} $currency'),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 14),
                            child: Divider(color: Color(0x22FFFFFF), height: 1),
                          ),
                          Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'Derniere verification requise',
                                  style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: recipientNameResolved ? const Color(0x2233D17A) : const Color(0x22FE6F0B),
                                  borderRadius: BorderRadius.circular(30),
                                ),
                                child: Text(
                                  recipientNameResolved ? 'Nom verifie' : 'Secure check',
                                  style: TextStyle(
                                    color: recipientNameResolved ? const Color(0xFF33D17A) : const Color(0xFFFE6F0B),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0x11FE6F0B),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0x22FE6F0B)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline, color: Color(0xFFFE6F0B), size: 18),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Verifie les informations du beneficiaire avant validation finale.',
                              style: TextStyle(color: Colors.white70, fontSize: 12.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  ),
);
}

Widget _buildConfirmationRow(
  String label,
  String value, {
  bool compact = false,
  bool allowWrap = false,
  double? valueFontSize,
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            maxLines: allowWrap ? 2 : 1,
            overflow: allowWrap ? TextOverflow.visible : TextOverflow.ellipsis,
            softWrap: allowWrap,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: Colors.white,
              fontSize: valueFontSize ?? (compact ? 11 : 14),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

Widget _buildOperationResultStep() {
  final status = lastOperationStatus ?? 'en_cours';
  final isSuccess = status == 'valide';
  final isFailure = status == 'echec';
  final statusLabel = isSuccess
      ? 'Operation validee'
      : isFailure
          ? 'Operation echouee'
          : 'Operation en cours';
  final statusColor = isSuccess
      ? const Color(0xFF33D17A)
      : isFailure
          ? const Color(0xFFFF5252)
          : const Color(0xFFFFB06D);

  return SingleChildScrollView(
    key: const ValueKey('operation_result'),
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
    child: TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.scale(
            scale: 0.92 + (value * 0.08),
            child: child,
          ),
        );
      },
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 560),
        padding: const EdgeInsets.all(1.2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: const LinearGradient(
            colors: [Color(0xFFFE6F0B), Color(0x44FE6F0B), Color(0x11FE6F0B)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x22FE6F0B),
              blurRadius: 24,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0A0A0A),
            borderRadius: BorderRadius.circular(27),
          ),
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _buildStatusIconWithAnimation(isSuccess, statusColor,
                      isFailure: isFailure),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Confirmation operation',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          statusLabel,
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF141414),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0x22FFFFFF)),
                ),
                child: Column(
                  children: [
                    _buildConfirmationRow('Transaction ID', lastOperationTxId ?? '-', valueFontSize: 13),
                    _buildConfirmationRow('Date', lastOperationDate ?? '-', valueFontSize: 13),
                    _buildConfirmationRow('Receveur', lastOperationReceiver ?? '-', compact: true, allowWrap: true),
                    _buildConfirmationRow('Reseau', '${lastOperationFrom ?? '-'} -> ${lastOperationTo ?? '-'}', compact: true, allowWrap: true),
                    _buildConfirmationRow(
                      'Montant',
                      '${lastOperationAmount ?? '-'} ${lastOperationCurrency ?? ''}'.trim(),
                      valueFontSize: 13,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0x11FE6F0B),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0x33FE6F0B)),
                ),
                child: Text(
                  lastOperationMessage ?? 'Votre operation a été enregistree.',
                  style: const TextStyle(
                    color: Color(0xFFE7E7E7),
                    fontSize: 13,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Widget _buildStatusIconWithAnimation(bool isSuccess, Color statusColor,
    {bool isFailure = false}) {
  if (isFailure) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: const Color(0x22FF5252),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x44FF5252)),
      ),
      child: Icon(Icons.close_rounded, color: statusColor, size: 30),
    );
  }
  if (isSuccess) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 1100),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        final iconOpacity = ((value - 0.62) / 0.38).clamp(0.0, 1.0);
        return Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: const Color(0x22FE6F0B),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0x44FE6F0B)),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 30,
                height: 30,
                child: CircularProgressIndicator(
                  value: value,
                  strokeWidth: 3,
                  backgroundColor: const Color(0x22FFFFFF),
                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF33D17A)),
                ),
              ),
              Opacity(
                opacity: iconOpacity,
                child: const Icon(
                  Icons.check_rounded,
                  color: Color(0xFF33D17A),
                  size: 28,
                ),
              ),
            ],
          ),
        );
      },
    );
  } else {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: const Color(0x22FE6F0B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x44FE6F0B)),
      ),
      child: Icon(
        Icons.schedule,
        color: statusColor,
        size: 30,
      ),
    );
  }
}

void _onContinuePressed({
required BuildContext context,
required int stepIndex,
required void Function(int) setStepIndex,
required TextEditingController amountController,
required TextEditingController sendController,
required TextEditingController receiveController,
required String selectedFrom,
required String selectedTo,
}) async {
final scaffold = ScaffoldMessenger.of(context);
scaffold.removeCurrentSnackBar();

// Visuel pour les étapes avant la dernière
if (stepIndex < 3) {
if (stepIndex == 1) {
  final sendErr = validateLocalNumberForProvider(selectedFrom, sendController.text);
  if (sendErr != null) {
    scaffold.showSnackBar(SnackBar(content: Text('Numéro d\'envoi invalide : $sendErr'), backgroundColor: Colors.red));
    return;
  }

  final receiveErr = validateLocalNumberForProvider(selectedTo, receiveController.text);
  if (receiveErr != null) {
    scaffold.showSnackBar(SnackBar(content: Text('Numéro de réception invalide : $receiveErr'), backgroundColor: Colors.red));
    return;
  }

}

if (stepIndex == 2) {
  final amount = enteredAmount;
  if (amount <= 0) {
    scaffold.showSnackBar(const SnackBar(content: Text('Montant invalide'), backgroundColor: Colors.red));
    return;
  }
  if (payoutAmount <= 0) {
    scaffold.showSnackBar(const SnackBar(content: Text('Montant insuffisant après frais'), backgroundColor: Colors.red));
    return;
  }
  // Résoudre le nom du bénéficiaire avant d'afficher le récapitulatif
  // (comme MTN MoMo : on confirme un nom, pas seulement un numéro).
  if (!recipientNameResolved && !recipientLookupInFlight) {
    _setProgress('Identification du bénéficiaire…');
    await _lookupRecipientIdentity();
    _setProgress('');
  }
}

final snack = SnackBar(
duration: const Duration(milliseconds: 900),
backgroundColor: Colors.white,
content: Row(
mainAxisAlignment: MainAxisAlignment.center,
children: [
  Text(
    stepIndex == 2
        ? 'Preparation du recapitulatif final'
        : 'Transfert de $selectedFrom vers $selectedTo',
    style: const TextStyle(color: Colors.black),
  ),
  const SizedBox(width: 8),
  const AnimatedDots(),
],
),
);
scaffold.showSnackBar(snack);
await Future.delayed(const Duration(milliseconds: 900));
if (stepIndex == 0) _rememberOperatorSelection();
setStepIndex(stepIndex + 1);
return;
}

// Dernière étape -> lancer transfert complet via le service
_setProgress('Validation des champs…');
final amountText = amountController.text.trim();
if (amountText.isEmpty) {
  _setProgress('');
  return;
}

final amount = double.tryParse(amountText);
if (amount == null || amount <= 0) {
scaffold.showSnackBar(const SnackBar(content: Text("Montant invalide")));
_setProgress('');
return;
}


// Préparer les numéros: garder uniquement les chiffres puis MSISDN sans '+' pour Pawapay
final senderDigits = digitsOnly(sendController.text);
final senderMsisdn = (providerPrefixes[selectedFrom] ?? '+') + senderDigits;
var sanitizedSender = senderMsisdn.replaceFirst('+', ''); // mutable pour correction automatique

final receiverDigits = digitsOnly(receiveController.text);
final receiverMsisdn = (providerPrefixes[selectedTo] ?? '+') + receiverDigits;
final sanitizedReceiver = receiverMsisdn.replaceFirst('+', '');

final senderValidation = validateLocalNumberForProvider(selectedFrom, senderDigits);
if (senderValidation != null) {
  _setProgress('');
  scaffold.showSnackBar(SnackBar(content: Text('Numéro d\'envoi invalide : $senderValidation'), backgroundColor: Colors.red));
  return;
}

final receiverValidation = validateLocalNumberForProvider(selectedTo, receiverDigits);
if (receiverValidation != null) {
  _setProgress('');
  scaffold.showSnackBar(SnackBar(content: Text('Numéro de réception invalide : $receiverValidation'), backgroundColor: Colors.red));
  return;
}

// Validation via predict-provider (via backend) pour éviter les erreurs d'initiation
_setProgress('Vérification du numéro…');
try {
final predictResp = await ApiClient.instance.postJson(
  '/api/predict-provider',
  {
    'phoneNumber': sanitizedSender,
    'expectedProvider': selectedFrom,
    // code PawaPay exact (si la liste dynamique est chargée) :
    // comparaison fiable côté serveur, sans devinette de libellés
    if (providerCodes[selectedFrom] != null)
      'expectedProviderCode': providerCodes[selectedFrom],
  },
  timeout: kColdStartTimeout,
);

if (predictResp.statusCode == 200) {
  _setProgress('Numéro validé');
final pd = jsonDecode(predictResp.body);
debugPrint('predict-result: $pd');
final predicted = pd['predicted'];
final matches = pd['matches'];

if (predicted != null) {
// handle API-level failure reason if present
if (predicted['failureReason'] != null) {
  final fr = predicted['failureReason'];
  final msg = fr['failureMessage'] ?? 'Erreur inconnue';
  scaffold.showSnackBar(SnackBar(content: Text('Prediction error: $msg'), backgroundColor: Colors.red));
  return;
}

final predictedNumber = predicted['phoneNumber'];
final predictedProvider = predicted['provider'];

if (predictedNumber != null) {
  final correction = tryNormalizeCorrection(sanitizedSender, predictedNumber as String);
  if (correction == null) {
    scaffold.showSnackBar(SnackBar(
        content: Text('Numéro invalide après nettoyage : $predictedNumber'),
        backgroundColor: Colors.red));
    return;
  }
  if (correction != normalize(sanitizedSender)) {
    final missing = correction.length - normalize(sanitizedSender).length;
    final extraInfo = missing > 0 ? " (il manque $missing chiffre${missing>1? 's':''})" : '';
    scaffold.showSnackBar(SnackBar(
      content: Text('Correction appliquée : $correction$extraInfo'),
      backgroundColor: Colors.orange),
    );
    sanitizedSender = correction; // corrigé pour l'appel suivant
  }
}

if (matches == false) {
  scaffold.showSnackBar(SnackBar(content: Text('Le numéro semble appartenir à $predictedProvider — vérifiez le fournisseur sélectionné.'), backgroundColor: Colors.red));
  return;
}

}
} else {
final err = predictResp.body.isNotEmpty ? jsonDecode(predictResp.body)['error'] ?? predictResp.body : 'Erreur prédiction';
scaffold.showSnackBar(SnackBar(content: Text('Impossible de valider le numéro : $err'), backgroundColor: Colors.red));
return;
}
} on TimeoutException {
scaffold.showSnackBar(const SnackBar(content: Text('Validation numéro : timeout'), backgroundColor: Colors.red));
return;
} catch (e) {
debugPrint('Erreur predict-provider: $e');
scaffold.showSnackBar(SnackBar(content: Text('Validation numéro échouée : $e'), backgroundColor: Colors.red));
return;
}

// Générer un depositId UUIDv4 (idempotence)
_setProgress('Préparation du transfert…');
final depositId = Uuid().v4();

// Currency and amount formatting (string, sans décimales si non supporté)
final currency = getCurrencyForProvider(selectedFrom);
final amountStr = amount.toStringAsFixed(0); // ajustez selon decimals supportés (active-conf)

final payload = {
"depositId": depositId,
"amount": amountStr,
"currency": currency,
"payer": {
"type": "MMO",
"accountDetails": {
"phoneNumber": sanitizedSender,
// code PawaPay exact si connu, sinon libellé (mappé côté serveur)
"provider": providerCodes[selectedFrom] ?? normalizeProvider(selectedFrom),
}
},
// Infos destinataire nécessaires pour créer le payout plus tard
"receiverPhone": sanitizedReceiver,
"receiverProvider": normalizeProvider(selectedTo),
if (providerCodes[selectedTo] != null)
  "receiverProviderCode": providerCodes[selectedTo],
"customerMessage": "Transfert $selectedFrom -> $selectedTo"
};

debugPrint("📤 Payload Pawapay (envoyé au backend) : ${jsonEncode(payload)}");

const maxRetries = 3;
int attempt = 0;
bool success = false;

while (attempt < maxRetries && !success) {
attempt++;
_setProgress('Envoi en cours (tentative $attempt)…');
try {
final response = await ApiClient.instance.postJson(
  '/api/transfer',
  payload,
  timeout: kColdStartTimeout,
);

final contentType = response.headers['content-type'] ?? '';
if (contentType.contains('application/json')) {
final data = jsonDecode(response.body);

if (response.statusCode == 200) {
  final depositObj = data['deposit'];

  // Erreur applicative renvoyée par PawaPay dans l'objet deposit
  if (depositObj is Map) {
    final errorCode = depositObj['errorCode'];
    final errorMessage = depositObj['errorMessage'];
    if (errorMessage != null || (errorCode != null && errorCode != 0)) {
      final errMsg = errorMessage ?? 'Erreur (code $errorCode)';
      debugPrint('⚠️ Erreur dépôt: $errMsg');
      scaffold.showSnackBar(SnackBar(content: Text('Erreur dépôt : $errMsg'), backgroundColor: Colors.red));
      break;
    }
  }

  // Statut réel renvoyé par le backend (ACCEPTED, COMPLETED, DUPLICATE_IGNORED…)
  final rawStatus =
      (data['status'] ?? (depositObj is Map ? depositObj['status'] : null) ?? '')
          .toString()
          .toUpperCase();
  const successStatuses = {'COMPLETED', 'SUCCESS', 'DUPLICATE_IGNORED'};
  final isCompleted = successStatuses.contains(rawStatus);
  final uiStatus = isCompleted ? 'valide' : 'en_cours';

  await HistoryStorage.prepend(
    HistoryRecord(
      id: depositId,
      from: selectedFrom,
      to: selectedTo,
      amount: '$amountStr $currency',
      status: uiStatus,
      date: HistoryStorage.formatDisplayDate(DateTime.now()),
    ),
  );
  _captureOperationResult(
    status: uiStatus,
    txId: depositId,
    amount: amountStr,
    currency: currency,
    message: isCompleted
        ? 'Le transfert a été validé avec succès.'
        : 'Dépôt initié — confirmation de l\'opérateur en cours…',
  );
  setStepIndex(4);
  success = true;
  _setProgress('');
  // Suivi du statut réel auprès du backend jusqu'à confirmation ou échec
  if (!isCompleted) {
    _startStatusPolling(depositId);
  }
  break;
} else if (response.statusCode == 401) {
  // jeton expiré ou invalide : retour à l'écran de connexion
  await ApiClient.instance.logout();
  scaffold.showSnackBar(const SnackBar(
      content: Text('Session expirée — reconnectez-vous.'),
      backgroundColor: Colors.red));
  widget.onLoggedOut?.call();
  break;
} else {
  final err = data['message'] ?? data['error'] ?? "Erreur ${response.statusCode}";
  scaffold.showSnackBar(SnackBar(content: Text("Erreur serveur : $err"), backgroundColor: Colors.red));
  break;
}
} else {
debugPrint("⚠️ Réponse inattendue: ${response.body}");
scaffold.showSnackBar(SnackBar(content: Text("Erreur serveur : réponse inattendue (${response.statusCode})"), backgroundColor: Colors.red));
break;
}
} on TimeoutException {
  if (attempt >= maxRetries) {
    scaffold.showSnackBar(const SnackBar(content: Text("Erreur réseau : Timeout"), backgroundColor: Colors.red));
  } else {
    await Future.delayed(const Duration(seconds: 1));
    continue;
  }
} catch (e) {
  debugPrint("Erreur envoi: $e");
  scaffold.showSnackBar(SnackBar(content: Text("Erreur réseau : $e"), backgroundColor: Colors.red));
  break;
} finally {
  if (success) _setProgress('');
}
}
}




Widget buildWheels(
FixedExtentScrollController fromController,
FixedExtentScrollController toController,
String selectedFrom,
String selectedTo,
Function(String) onFromChanged,
Function(String) onToChanged,
) {
return SizedBox(
height: 200,
child: Stack(
alignment: Alignment.center,
children: [
  Container(
    width: MediaQuery.of(context).size.width * 0.84,
    height: 50,
    decoration: BoxDecoration(
      color: Colors.black,
      border: Border.all(color: Colors.orange, width: 0.2),
      borderRadius: BorderRadius.circular(56),
    ),
    child: Center(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.82,
        height: 43,
        decoration: BoxDecoration(
          color: const Color(0x1AFFFFFF),
          borderRadius: BorderRadius.circular(44),
        ),
      ),
    ),
  ),
  Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      SizedBox(
        width: 150,
        height: 200,
        child: ListWheelScrollView.useDelegate(
          controller: fromController,
          itemExtent: 50,
          physics: const FixedExtentScrollPhysics(),
          overAndUnderCenterOpacity: 1.0,
          perspective: 0.003,
          onSelectedItemChanged: (index) {
            onFromChanged(providers[index]);
          },
          childDelegate: ListWheelChildBuilderDelegate(
            builder: (context, index) {
              if (index < 0 || index >= providers.length) return null;
              bool isSelected = providers[index] == selectedFrom;
              return Center(
                child: Text(
                  providers[index],
                  style: TextStyle(
                    fontSize: isSelected ? 20 : 16,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? Colors.white : Colors.grey,
                  ),
                ),
              );
            },
            childCount: providers.length,
          ),
        ),
      ),
      SizedBox(
        width: 150,
        height: 200,
        child: ListWheelScrollView.useDelegate(
          controller: toController,
          itemExtent: 50,
          physics: const FixedExtentScrollPhysics(),
          overAndUnderCenterOpacity: 1.0,
          perspective: 0.003,
          onSelectedItemChanged: (index) {
            onToChanged(providers[index]);
          },
          childDelegate: ListWheelChildBuilderDelegate(
            builder: (context, index) {
              if (index < 0 || index >= providers.length) return null;
              bool isSelected = providers[index] == selectedTo;
              return Center(
                child: Text(
                  providers[index],
                  style: TextStyle(
                    fontSize: isSelected ? 20 : 16,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? Colors.white : Colors.grey,
                  ),
                ),
              );
            },
            childCount: providers.length,
          ),
        ),
      ),
    ],
  ),
],
),
);
}

Widget buildCustomTabBar() {
return Padding(
padding: const EdgeInsets.symmetric(horizontal: 20),
child: Row(
mainAxisAlignment: MainAxisAlignment.center,
children: [
  buildTabItem("Transfert", 0),
  const SizedBox(width: 30),
  buildTabItem("Historique", 1),
],
),
);
}

Widget buildTabItem(String title, int index) {
bool isActive = selectedTab == index;
return GestureDetector(
onTap: () {
setState(() {
  selectedTab = index;
  tabController.animateTo(index);
});
},
child: SizedBox(
width: 100,
height: 76,
child: Stack(
  alignment: Alignment.center,
  children: [
    Positioned(
      top: 10,
      child: Text(
        title,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: isActive ? Colors.white : Colors.grey,
        ),
      ),
    ),
    if (isActive)
      Positioned(
        bottom: 8,
        child: SizedBox(
          height: 55,
          width: 300,
          child: Image.asset('assets/underline.png', fit: BoxFit.contain),
        ),
      ),
  ],
),
),
);
}
}

class AnimatedDots extends StatefulWidget {
const AnimatedDots({super.key});

@override
State<AnimatedDots> createState() => _AnimatedDotsState();
}

class _AnimatedDotsState extends State<AnimatedDots> with SingleTickerProviderStateMixin {
late AnimationController _controller;

@override
void initState() {
super.initState();
_controller = AnimationController(
duration: const Duration(milliseconds: 900),
vsync: this,
)..repeat();
}

@override
void dispose() {
_controller.dispose();
super.dispose();
}

Widget buildDot(int index) {
return AnimatedBuilder(
animation: _controller,
builder: (context, child) {
final double offset = sin((_controller.value * 2 * pi) + (index * pi / 3)) * 2.5;
return Transform.translate(
  offset: Offset(0, -offset),
  child: child,
);
},
child: const Padding(
padding: EdgeInsets.symmetric(horizontal: 4),
child: CircleAvatar(radius: 4, backgroundColor: Colors.black),
),
);
}

@override
Widget build(BuildContext context) {
return SizedBox(
height: 20,
child: Row(
mainAxisSize: MainAxisSize.min,
children: List.generate(3, buildDot),
),
);
}
}

class CustomInputFieldWithFixedPrefix extends StatelessWidget {
final String label;
final String prefix;
final TextEditingController controller;
final Function(String)? onChanged;
final String? errorText;
final String? helperText;
final bool helperIsSuccess;
final bool helperIsWarning;
final int? maxLength;

const CustomInputFieldWithFixedPrefix({
required this.label,
required this.prefix,
required this.controller,
this.onChanged,
this.errorText,
this.helperText,
this.helperIsSuccess = false,
this.helperIsWarning = false,
this.maxLength,
super.key,
});

@override
Widget build(BuildContext context) {
return TextField(
      controller: controller,
      onChanged: onChanged,
  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
  maxLength: maxLength,
  buildCounter: (
    BuildContext context, {
    required int currentLength,
    required bool isFocused,
    required int? maxLength,
  }) => null,
      style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.bold
      ),
      cursorColor: const Color(0xFFFE6F0B),
      keyboardType: TextInputType.phone,
      decoration: InputDecoration(
        filled: true,
        fillColor: const Color(0xFF1C1C1C),
        labelText: label,
        labelStyle: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500
        ),
        helperText: helperText,
        helperMaxLines: 2,
        helperStyle: TextStyle(
          color: helperIsSuccess
              ? Colors.greenAccent
              : helperIsWarning
                  ? const Color(0xFFFFB74D)
                  : Colors.white54,
          fontSize: 12,
          fontWeight: helperIsSuccess || helperIsWarning
              ? FontWeight.w600
              : FontWeight.normal,
        ),
        errorText: errorText,
        prefixText: '$prefix ',
        prefixStyle: const TextStyle(
            color: Color(0xFFFE6F0B),
            fontSize: 16,
            fontWeight: FontWeight.bold
        ),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFFE6F0B))
        ),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFFE6F0B))
        ),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFFE6F0B), width: 2)
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      ),
    );
  }
}