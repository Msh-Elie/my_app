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
import 'operator_picker.dart';
import 'operators.dart';
import 'theme.dart';
import 'ui_kit.dart';

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
  final VoidCallback? onLoggedOut;

  const HomePage({super.key, this.onLoggedOut});

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

// libellé -> l'opérateur sait-il *recevoir* un versement ?
// Renseigné par /api/providers. Un opérateur peut être joignable à l'envoi
// sans l'être à la réception : on refuse alors de le proposer en destination
// plutôt que de laisser l'utilisateur échouer au dernier moment.
Map<String, bool> providerPayoutCapable = {};

// libellé -> l'opérateur sait-il *émettre* un paiement ? Symétrique du
// précédent : un rail dont la clé d'API n'est pas configurée côté serveur ne
// peut servir ni de source ni de destination.
Map<String, bool> providerDepositCapable = {};

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
    final newPayoutCapable = <String, bool>{};
    final newDepositCapable = <String, bool>{};
    for (final p in list) {
      final label = p['label']?.toString() ?? '';
      final code = p['code']?.toString() ?? '';
      final prefix = p['prefix']?.toString() ?? '';
      if (label.isEmpty || code.isEmpty || prefix.isEmpty) continue;
      newProviders.add(label);
      newPrefixes[label] = prefix;
      newCodes[label] = code;
      // Absence de `capabilities` = ancien serveur : on suppose capable.
      final caps = p['capabilities'];
      newPayoutCapable[label] =
          caps is Map ? caps['payout'] != false : true;
      newDepositCapable[label] =
          caps is Map ? caps['deposit'] != false : true;
    }
    if (newProviders.isEmpty || !mounted) return;

    setState(() {
      providers = newProviders;
      providerPrefixes = newPrefixes;
      providerCodes = newCodes;
      providerPayoutCapable = newPayoutCapable;
      providerDepositCapable = newDepositCapable;
      if (!providers.contains(selectedFrom)) selectedFrom = providers.first;
      if (!providers.contains(selectedTo)) selectedTo = providers.first;
      _rememberOperatorSelection();
    });
  } catch (_) {
    // serveur injoignable : on garde la liste statique
  }
}

String selectedFrom = _OperatorSelectionSession.defaultProvider;
String selectedTo = _OperatorSelectionSession.defaultProvider;

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
/// Lien de paiement à ouvrir quand l'opérateur exige une validation sur
/// une page externe (cas des rails hors PawaPay).
String? lastOperationCheckoutUrl;

String _resolvedSessionProvider(String provider) {
  return providers.contains(provider)
      ? provider
      : _OperatorSelectionSession.defaultProvider;
}

void _rememberOperatorSelection() {
  _OperatorSelectionSession.selectedFrom = selectedFrom;
  _OperatorSelectionSession.selectedTo = selectedTo;
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

sendController = TextEditingController();
receiveController = TextEditingController();
amountController = TextEditingController();

}

@override
void dispose() {
recipientLookupDebounce?.cancel();
statusPollTimer?.cancel();
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
  if (digits.isEmpty) return 'Bénéficiaire à renseigner';
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
      recipientLookupMessage = 'Identification en cours…';
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
        recipientLookupMessage = 'Bénéficiaire : $displayName';
      } else if (source == 'derived' && displayName != null && displayName.isNotEmpty) {
        recipientLookupMessage = 'Identité estimée : $displayName';
      } else {
        recipientLookupMessage = 'Identité non confirmée par l\'opérateur';
      }
    });
  } on TimeoutException {
    if (!mounted || currentVersion != recipientLookupVersion) return;
    setState(() {
      recipientLookupInFlight = false;
      recipientNameResolved = false;
      resolvedRecipientName = null;
      recipientLookupMessage = 'Identité non confirmée par l\'opérateur';
    });
  } catch (_) {
    if (!mounted || currentVersion != recipientLookupVersion) return;
    setState(() {
      recipientLookupInFlight = false;
      recipientNameResolved = false;
      resolvedRecipientName = null;
      recipientLookupMessage = 'Identité non confirmée par l\'opérateur';
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
  if (stepIndex == 2) return 'Voir le récapitulatif';
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
  String? checkoutUrl,
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
  lastOperationCheckoutUrl = checkoutUrl;
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
    lastOperationCheckoutUrl = null;
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
  return 'Numéro valide pour $selectedFrom';
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
  return 'Numéro valide pour $selectedTo';
}

// =========================================================================
// Interface
// =========================================================================

/// Libellés des étapes du tunnel de transfert, affichés par [StepProgress].
static const List<String> _stepLabels = [
  'Choix des opérateurs',
  'Numéros de téléphone',
  'Montant à envoyer',
  'Vérification finale',
];

/// L'opérateur de destination sait-il recevoir un versement ?
///
/// Renseigné par `/api/providers` (champ `capabilities.payout`). Certains
/// opérateurs sont joignables à l'envoi sans l'être à la réception : mieux
/// vaut le dire ici que laisser l'utilisateur aller au bout du tunnel pour
/// se faire refuser au moment de l'envoi.
bool get destinationCanReceive => providerPayoutCapable[selectedTo] ?? true;

/// L'opérateur de départ sait-il émettre un paiement ?
bool get sourceCanSend => providerDepositCapable[selectedFrom] ?? true;

/// Message expliquant pourquoi le trajet choisi est refusé, s'il l'est.
String? get blockedRouteMessage {
  if (!sourceCanSend) {
    return '$selectedFrom ne peut pas encore émettre de transfert. '
        'Choisissez un autre opérateur de départ.';
  }
  if (!destinationCanReceive) {
    return '$selectedTo ne peut pas encore recevoir de transfert. '
        'Choisissez un autre opérateur de destination.';
  }
  return null;
}

@override
Widget build(BuildContext context) {
  final c = context.colors;

  return Scaffold(
    resizeToAvoidBottomInset: false,
    body: SafeArea(
      child: Column(
        children: [
          _buildHeader(),
          _buildTabs(),
          Expanded(
            child: selectedTab == 0 ? _buildTransferTab() : const HistoryContent(embedded: true),
          ),
          if (selectedTab == 0) _buildBottomBar(),
        ],
      ),
    ),
    bottomNavigationBar: inProgress
        ? Container(
            color: c.surface,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: c.brand),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      progressText,
                      style: context.text.bodyMedium?.copyWith(color: c.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
          )
        : null,
  );
}

/// En-tête : signature de l'application à gauche, accès au compte à droite.
Widget _buildHeader() {
  final c = context.colors;
  final user = ApiClient.instance.user;
  final initial = (user?.name.trim().isNotEmpty ?? false)
      ? user!.name.trim().characters.first.toUpperCase()
      : '?';

  return Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.md,
      AppSpacing.md,
      AppSpacing.sm,
    ),
    child: Row(
      children: [
        const BrandMark(size: 34),
        const Spacer(),
        GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => MenuPage(onLoggedOut: widget.onLoggedOut),
              ),
            ).then((_) {
              if (mounted) setState(() {});
            });
          },
          child: Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.surface,
              shape: BoxShape.circle,
              border: Border.all(color: c.border),
            ),
            child: Text(
              initial,
              style: context.text.titleSmall?.copyWith(color: c.textSecondary),
            ),
          ),
        ),
      ],
    ),
  );
}

/// Onglets Transfert / Historique.
///
/// L'indicateur est dessiné en code et animé : l'image `underline.png`
/// étirée sous l'onglet actif était l'un des détails qui trahissaient le
/// prototype.
Widget _buildTabs() {
  final c = context.colors;

  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
    child: Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          _buildTabItem('Transfert', 0),
          _buildTabItem('Historique', 1),
        ],
      ),
    ),
  );
}

Widget _buildTabItem(String title, int index) {
  final c = context.colors;
  final isActive = selectedTab == index;

  return Expanded(
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() {
          selectedTab = index;
          tabController.animateTo(index);
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? c.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          boxShadow: isActive ? c.cardShadow : null,
        ),
        child: Text(
          title,
          textAlign: TextAlign.center,
          style: context.text.titleSmall?.copyWith(
            color: isActive ? c.textPrimary : c.textMuted,
          ),
        ),
      ),
    ),
  );
}

/// Onglet « Transfert » : progression, trajet, contenu de l'étape.
Widget _buildTransferTab() {
  final showFlowChrome = stepIndex < 4;

  return Column(
    children: [
      if (showFlowChrome)
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            0,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (stepIndex > 0)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: _BackChip(onTap: _goToPreviousStep),
                ),
              Expanded(
                child: StepProgress(
                  currentStep: stepIndex,
                  totalSteps: 4,
                  labels: _stepLabels,
                ),
              ),
            ],
          ),
        ),
      if (showFlowChrome && stepIndex > 0)
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            0,
          ),
          child: _buildRouteSummary(),
        ),
      Expanded(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 320),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeIn,
          // Par défaut AnimatedSwitcher empile ses enfants centrés : une étape
          // au contenu court flottait au milieu de l'écran, laissant un grand
          // vide sous la barre de progression. On aligne donc en haut.
          layoutBuilder: (currentChild, previousChildren) => Stack(
            alignment: Alignment.topCenter,
            children: [...previousChildren, if (currentChild != null) currentChild],
          ),
          transitionBuilder: (child, animation) {
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.06, 0),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            );
          },
          child: SizedBox(
            key: ValueKey(stepIndex),
            width: double.infinity,
            child: _buildStepContent(),
          ),
        ),
      ),
    ],
  );
}

void _goToPreviousStep() {
  if (stepIndex <= 0) return;
  setState(() => stepIndex = stepIndex - 1);
}

/// Rappel permanent du trajet choisi : « MTN BJ → MOOV BJ ».
Widget _buildRouteSummary() {
  final c = context.colors;

  return Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.md,
    ),
    decoration: BoxDecoration(
      color: c.surface,
      borderRadius: BorderRadius.circular(AppRadius.md),
      border: Border.all(color: c.border),
    ),
    child: Row(
      children: [
        OperatorAvatar(label: selectedFrom, size: 32),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: _RouteEnd(label: 'Depuis', value: selectedFrom)),
        Container(
          width: 26,
          height: 26,
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          decoration: BoxDecoration(
            color: c.brandSurface,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.arrow_forward_rounded, size: 14, color: c.brandText),
        ),
        Expanded(
          child: _RouteEnd(
            label: 'Vers',
            value: selectedTo,
            alignEnd: true,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        OperatorAvatar(label: selectedTo, size: 32),
      ],
    ),
  );
}

Widget _buildStepContent() {
  return switch (stepIndex) {
    4 => _buildResultStep(),
    3 => _buildConfirmationStep(),
    2 => _buildAmountStep(),
    1 => _buildNumbersStep(),
    _ => _buildOperatorStep(),
  };
}

// ---- Étape 0 : choix des opérateurs -------------------------------------

Widget _buildOperatorStep() {
  final c = context.colors;

  return SingleChildScrollView(
    key: const ValueKey('operators'),
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.lg,
      AppSpacing.lg,
      AppSpacing.lg,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('D\'où vers où ?', style: context.text.headlineSmall),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Touchez une carte pour choisir l\'opérateur.',
          style: context.text.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.lg),

        // Les deux extrémités du trajet, séparées par le bouton d'inversion.
        // Le bouton chevauche les cartes : il appartient visuellement aux
        // deux, ce qui rend son effet évident.
        Stack(
          alignment: Alignment.center,
          children: [
            Column(
              children: [
                OperatorSelectorCard(
                  caption: 'Depuis',
                  label: selectedFrom,
                  prefix: providerPrefixes[selectedFrom] ?? '',
                  warning: sourceCanSend ? null : 'indisponible',
                  onTap: () => _pickOperator(isSource: true),
                ),
                const SizedBox(height: AppSpacing.md),
                OperatorSelectorCard(
                  caption: 'Vers',
                  label: selectedTo,
                  prefix: providerPrefixes[selectedTo] ?? '',
                  warning: destinationCanReceive ? null : 'indisponible',
                  onTap: () => _pickOperator(isSource: false),
                ),
              ],
            ),
            Positioned(
              right: AppSpacing.lg,
              child: SwapDirectionButton(onSwap: _swapOperators),
            ),
          ],
        ),

        if (blockedRouteMessage != null) ...[
          const SizedBox(height: AppSpacing.md),
          InfoBanner(
            message: blockedRouteMessage!,
            tone: Tone.warning,
            icon: Icons.block_rounded,
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Icon(Icons.lock_outline_rounded, size: 14, color: c.textMuted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Opérateurs fournis en direct par les réseaux partenaires.',
                style: context.text.bodySmall,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

/// Inverse le sens du transfert. Les numéros suivent les opérateurs : ils
/// resteraient faux s'ils restaient en place, et la recherche d'identité du
/// bénéficiaire doit être relancée.
void _swapOperators() {
  setState(() {
    final from = selectedFrom;
    selectedFrom = selectedTo;
    selectedTo = from;

    final sendText = sendController.text;
    sendController.text = receiveController.text;
    receiveController.text = sendText;

    _rememberOperatorSelection();
    _resetRecipientLookup();
  });
}

/// Ouvre la feuille de sélection pour l'une des deux extrémités.
Future<void> _pickOperator({required bool isSource}) async {
  final options = [
    for (final label in providers)
      OperatorOption(
        label: label,
        prefix: providerPrefixes[label] ?? '',
        // Un opérateur n'est proposé que pour les sens qu'il sait assurer.
        available: isSource
            ? (providerDepositCapable[label] ?? true)
            : (providerPayoutCapable[label] ?? true),
        unavailableReason: isSource
            ? 'Ne peut pas encore émettre'
            : 'Ne peut pas encore recevoir',
      ),
  ];

  final picked = await showOperatorPicker(
    context,
    title: isSource ? 'Envoyer depuis' : 'Envoyer vers',
    selected: isSource ? selectedFrom : selectedTo,
    options: options,
  );
  if (picked == null || !mounted) return;

  setState(() {
    if (isSource) {
      selectedFrom = picked;
    } else {
      selectedTo = picked;
      _resetRecipientLookup();
    }
    _rememberOperatorSelection();
  });
}


// ---- Étape 1 : numéros ---------------------------------------------------

Widget _buildNumbersStep() {
  return SingleChildScrollView(
    key: const ValueKey('numbers'),
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.lg,
      AppSpacing.lg,
      AppSpacing.lg,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Les numéros', style: context.text.headlineSmall),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Le numéro qui envoie, puis celui qui reçoit.',
          style: context.text.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.lg),
        CustomInputFieldWithFixedPrefix(
          label: 'Numéro d\'envoi',
          prefix: providerPrefixes[selectedFrom] ?? '+XXX',
          controller: sendController,
          errorText: sendNumberError,
          helperText: sendNumberWarning ??
              sendNumberSuccess ??
              numberHintForProvider(selectedFrom),
          helperIsSuccess: sendNumberSuccess != null,
          helperIsWarning: sendNumberWarning != null,
          maxLength: 10,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppSpacing.lg),
        CustomInputFieldWithFixedPrefix(
          label: 'Numéro de réception',
          prefix: providerPrefixes[selectedTo] ?? '+XXX',
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
          isLoading: recipientLookupInFlight,
          maxLength: 10,
          onChanged: (_) {
            setState(() {});
            _scheduleRecipientLookup();
          },
        ),
      ],
    ),
  );
}

// ---- Étape 2 : montant ---------------------------------------------------

Widget _buildAmountStep() {
  final c = context.colors;
  final currency = transferCurrency;
  final hasAmount = amountController.text.trim().isNotEmpty && enteredAmount > 0;

  return SingleChildScrollView(
    key: const ValueKey('amount'),
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.lg,
      AppSpacing.lg,
      AppSpacing.lg,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Combien envoyer ?', style: context.text.headlineSmall),
        const SizedBox(height: AppSpacing.lg),

        // Saisie du montant, traitée comme l'élément principal de l'écran.
        AppCard(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.xl,
            AppSpacing.lg,
            AppSpacing.xl,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: TextField(
                  controller: amountController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textAlign: TextAlign.center,
                  autofocus: true,
                  cursorColor: c.brand,
                  style: context.text.displaySmall?.copyWith(
                    fontSize: 40,
                    fontFeatures: kTabularFigures,
                  ),
                  decoration: InputDecoration(
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    hintText: '0',
                    hintStyle: context.text.displaySmall?.copyWith(
                      fontSize: 40,
                      color: c.textMuted,
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  currency,
                  style: context.text.titleMedium?.copyWith(color: c.brandText),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: AppSpacing.md),

        // Décomposition des frais : visible avant la confirmation, pas après.
        AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: hasAmount ? 1 : 0.35,
          child: AppCard(
            child: Column(
              children: [
                DetailRow(
                  label: 'Montant envoyé',
                  value: '${formatThousands(enteredAmount.toStringAsFixed(0))} $currency',
                ),
                DetailRow(
                  label: 'Frais de service',
                  value: '${formatThousands(transferFee.toStringAsFixed(0))} $currency',
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Divider(height: 1, color: c.border),
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text('Le bénéficiaire reçoit',
                          style: context.text.titleSmall),
                    ),
                    AnimatedAmount(
                      value: payoutAmount,
                      currency: currency,
                      style: context.text.titleLarge?.copyWith(
                        color: c.brandText,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

// ---- Étape 3 : confirmation ---------------------------------------------

Widget _buildConfirmationStep() {
  final c = context.colors;
  final currency = transferCurrency;
  final receiverPhone = _formatPhonePreview(selectedTo, receiveController.text);
  final senderPhone = _formatPhonePreview(selectedFrom, sendController.text);

  return SingleChildScrollView(
    key: const ValueKey('confirmation'),
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.lg,
      AppSpacing.lg,
      AppSpacing.lg,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Le bénéficiaire d'abord : c'est l'information qu'on vérifie avant
        // de valider un envoi d'argent.
        AppCard(
          highlighted: true,
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            children: [
              // Les deux opérateurs concernés, pour que le trajet soit
              // reconnaissable d'un coup d'œil au moment de valider.
              OperatorPair(from: selectedFrom, to: selectedTo, size: 52),
              const SizedBox(height: AppSpacing.lg),
              Text(
                resolvedRecipientDisplayName,
                textAlign: TextAlign.center,
                style: context.text.titleLarge,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                receiverPhone,
                textAlign: TextAlign.center,
                style: context.text.bodyMedium?.copyWith(
                  fontFeatures: kTabularFigures,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              StatusPill(
                label: recipientNameResolved
                    ? 'Identité vérifiée'
                    : 'Identité non confirmée',
                tone: recipientNameResolved ? Tone.success : Tone.warning,
                icon: recipientNameResolved
                    ? Icons.verified_rounded
                    : Icons.help_outline_rounded,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                child: Divider(height: 1, color: c.border),
              ),
              DetailRow(label: 'Réseau', value: selectedTo),
              DetailRow(
                label: 'Expéditeur',
                value: senderPhone,
                allowWrap: true,
              ),
            ],
          ),
        ),

        const SizedBox(height: AppSpacing.md),

        // Le détail financier ensuite.
        AppCard(
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Total débité', style: context.text.titleSmall),
                  ),
                  Text(
                    '${formatThousands(enteredAmount.toStringAsFixed(0))} $currency',
                    style: context.text.headlineSmall?.copyWith(
                      fontFeatures: kTabularFigures,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              DetailRow(
                label: 'Dont frais',
                value: '${formatThousands(transferFee.toStringAsFixed(0))} $currency',
              ),
              DetailRow(
                label: 'Montant reçu',
                value: '${formatThousands(payoutAmount.toStringAsFixed(0))} $currency',
                emphasize: true,
              ),
            ],
          ),
        ),

        const SizedBox(height: AppSpacing.md),
        const InfoBanner(
          message: 'Vérifiez le nom et le numéro du bénéficiaire : un '
              'transfert validé ne peut pas être annulé.',
          icon: Icons.shield_outlined,
        ),
      ],
    ),
  );
}

// ---- Étape 4 : résultat --------------------------------------------------

Widget _buildResultStep() {
  final c = context.colors;
  final status = lastOperationStatus ?? 'en_cours';
  final isSuccess = status == 'valide';
  final isFailure = status == 'echec';

  final tone = isSuccess
      ? Tone.success
      : isFailure
          ? Tone.danger
          : Tone.warning;
  final statusLabel = isSuccess
      ? 'Transfert validé'
      : isFailure
          ? 'Transfert échoué'
          : 'Transfert en cours';
  final icon = isSuccess
      ? Icons.check_rounded
      : isFailure
          ? Icons.close_rounded
          : Icons.schedule_rounded;

  return SingleChildScrollView(
    key: const ValueKey('result'),
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.xl,
      AppSpacing.lg,
      AppSpacing.lg,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 520),
            curve: Curves.easeOutBack,
            builder: (context, value, child) =>
                Transform.scale(scale: 0.7 + (value * 0.3), child: child),
            // Le succès se dessine (anneau puis coche) ; l'échec et l'attente
            // restent sobres — on ne met pas en scène une mauvaise nouvelle.
            child: isSuccess
                ? AnimatedCheck(
                    size: 76,
                    color: tone.foreground(context),
                    background: tone.background(context),
                  )
                : Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      color: tone.background(context),
                      shape: BoxShape.circle,
                    ),
                    child: isFailure
                        ? Icon(icon, size: 38, color: tone.foreground(context))
                        : Center(
                            child: SizedBox(
                              width: 26,
                              height: 26,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.6,
                                color: tone.foreground(context),
                              ),
                            ),
                          ),
                  ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(statusLabel, textAlign: TextAlign.center, style: context.text.headlineSmall),
        const SizedBox(height: AppSpacing.xs),
        Text(
          lastOperationMessage ?? 'Votre opération a été enregistrée.',
          textAlign: TextAlign.center,
          style: context.text.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.xl),
        AppCard(
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Montant', style: context.text.titleSmall),
                  ),
                  Text(
                    formatAmountLabel('${lastOperationAmount ?? '-'} ${lastOperationCurrency ?? ''}'.trim()),
                    style: context.text.titleLarge?.copyWith(
                      fontFeatures: kTabularFigures,
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Divider(height: 1, color: c.border),
              ),
              DetailRow(
                label: 'Bénéficiaire',
                value: lastOperationReceiver ?? '-',
                allowWrap: true,
              ),
              DetailRow(
                label: 'Trajet',
                value: '${lastOperationFrom ?? '-'} → ${lastOperationTo ?? '-'}',
                allowWrap: true,
              ),
              DetailRow(label: 'Date', value: lastOperationDate ?? '-'),
              DetailRow(
                label: 'Référence',
                value: lastOperationTxId ?? '-',
                allowWrap: true,
              ),
            ],
          ),
        ),
        // Certains opérateurs (hors réseau PawaPay) exigent que le client
        // valide son paiement sur une page dédiée : on lui donne le lien.
        if (lastOperationCheckoutUrl != null) ...[
          const SizedBox(height: AppSpacing.md),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.open_in_new_rounded, size: 18, color: c.brandText),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text('Validation à finaliser',
                          style: context.text.titleSmall),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Ouvrez ce lien pour confirmer le paiement auprès de votre '
                  'opérateur, puis revenez dans l\'application.',
                  style: context.text.bodySmall,
                ),
                const SizedBox(height: AppSpacing.md),
                SelectableText(
                  lastOperationCheckoutUrl!,
                  style: context.text.bodySmall?.copyWith(color: c.brandText),
                ),
                const SizedBox(height: AppSpacing.md),
                OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(
                        ClipboardData(text: lastOperationCheckoutUrl!));
                    showAppSnack(context, 'Lien copié', tone: Tone.success);
                  },
                  icon: const Icon(Icons.copy_rounded, size: 17),
                  label: const Text('Copier le lien'),
                ),
              ],
            ),
          ),
        ],
      ],
    ),
  );
}

// ---- Barre d'action -----------------------------------------------------

Widget _buildBottomBar() {
  final c = context.colors;
  final blockedRoute = stepIndex < 4 && blockedRouteMessage != null;

  return Container(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.md,
      AppSpacing.lg,
      AppSpacing.md,
    ),
    decoration: BoxDecoration(
      color: c.canvas,
      border: Border(top: BorderSide(color: c.border)),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PrimaryButton(
          label: continueLabel,
          onPressed: (isContinueActive && !blockedRoute)
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
        ),
        if (stepIndex < 3) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            'En continuant, vous acceptez nos conditions d\'utilisation '
            'et notre politique de confidentialité.',
            textAlign: TextAlign.center,
            style: context.text.bodySmall?.copyWith(fontSize: 11.5),
          ),
        ],
      ],
    ),
  );
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
    showSnackOn(scaffold, 'Numéro d\'envoi invalide : $sendErr', tone: Tone.danger);
    return;
  }

  final receiveErr = validateLocalNumberForProvider(selectedTo, receiveController.text);
  if (receiveErr != null) {
    showSnackOn(scaffold, 'Numéro de réception invalide : $receiveErr', tone: Tone.danger);
    return;
  }

}

if (stepIndex == 2) {
  final amount = enteredAmount;
  if (amount <= 0) {
    showSnackOn(scaffold, 'Montant invalide', tone: Tone.danger);
    return;
  }
  if (payoutAmount <= 0) {
    showSnackOn(scaffold, 'Montant insuffisant après frais', tone: Tone.danger);
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

// Passage à l'étape suivante : l'indicateur de progression rend compte
// du changement, une notification en bas d'écran ferait doublon.
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
showSnackOn(scaffold, 'Montant invalide', tone: Tone.danger);
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
  showSnackOn(scaffold, 'Numéro d\'envoi invalide : $senderValidation', tone: Tone.danger);
  return;
}

final receiverValidation = validateLocalNumberForProvider(selectedTo, receiverDigits);
if (receiverValidation != null) {
  _setProgress('');
  showSnackOn(scaffold, 'Numéro de réception invalide : $receiverValidation', tone: Tone.danger);
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
  showSnackOn(scaffold, 'Vérification du numéro impossible : $msg', tone: Tone.danger);
  return;
}

final predictedNumber = predicted['phoneNumber'];
final predictedProvider = predicted['provider'];

if (predictedNumber != null) {
  final correction = tryNormalizeCorrection(sanitizedSender, predictedNumber as String);
  if (correction == null) {
    showSnackOn(scaffold, 'Numéro invalide après nettoyage : $predictedNumber',
        tone: Tone.danger);
    return;
  }
  if (correction != normalize(sanitizedSender)) {
    final missing = correction.length - normalize(sanitizedSender).length;
    final extraInfo = missing > 0 ? " (il manque $missing chiffre${missing>1? 's':''})" : '';
    showSnackOn(scaffold, 'Correction appliquée : $correction$extraInfo',
        tone: Tone.warning);
    sanitizedSender = correction; // corrigé pour l'appel suivant
  }
}

if (matches == false) {
  showSnackOn(scaffold,
      'Ce numéro semble appartenir à $predictedProvider — vérifiez l\'opérateur sélectionné.',
      tone: Tone.danger);
  return;
}

}
} else {
final err = predictResp.body.isNotEmpty ? jsonDecode(predictResp.body)['error'] ?? predictResp.body : 'Erreur prédiction';
showSnackOn(scaffold, 'Impossible de valider le numéro : $err', tone: Tone.danger);
return;
}
} on TimeoutException {
showSnackOn(scaffold, 'Vérification du numéro : délai dépassé', tone: Tone.danger);
return;
} catch (e) {
debugPrint('Erreur predict-provider: $e');
showSnackOn(scaffold, 'Vérification du numéro échouée : $e', tone: Tone.danger);
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
      showSnackOn(scaffold, 'Erreur lors du dépôt : $errMsg', tone: Tone.danger);
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
  final checkoutUrl = data['checkoutUrl']?.toString();
  _captureOperationResult(
    status: uiStatus,
    txId: depositId,
    amount: amountStr,
    currency: currency,
    checkoutUrl: checkoutUrl,
    message: checkoutUrl != null
        ? 'Finalisez le paiement sur la page de votre opérateur pour que '
            'le transfert soit exécuté.'
        : isCompleted
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
  showSnackOn(scaffold, 'Session expirée — reconnectez-vous.', tone: Tone.danger);
  widget.onLoggedOut?.call();
  break;
} else if (response.statusCode == 503 &&
    data['error'] == 'payout_rail_unavailable') {
  // Le serveur a refusé *avant* tout prélèvement : on relaie son message
  // tel quel, il explique précisément quel opérateur est indisponible.
  showSnackOn(
    scaffold,
    data['message']?.toString() ??
        'Cet opérateur ne peut pas encore recevoir de transfert.',
    tone: Tone.warning,
    duration: const Duration(seconds: 6),
  );
  break;
} else {
  final err = data['message'] ?? data['error'] ?? "Erreur ${response.statusCode}";
  showSnackOn(scaffold, 'Erreur serveur : $err', tone: Tone.danger);
  break;
}
} else {
debugPrint("⚠️ Réponse inattendue: ${response.body}");
showSnackOn(scaffold, 'Réponse inattendue du serveur (${response.statusCode})', tone: Tone.danger);
break;
}
} on TimeoutException {
  if (attempt >= maxRetries) {
    showSnackOn(scaffold, 'Erreur réseau : délai dépassé', tone: Tone.danger);
  } else {
    await Future.delayed(const Duration(seconds: 1));
    continue;
  }
} catch (e) {
  debugPrint("Erreur envoi: $e");
  showSnackOn(scaffold, 'Erreur réseau : $e', tone: Tone.danger);
  break;
} finally {
  if (success) _setProgress('');
}
}
}
}

/// Bouton de retour à l'étape précédente.
class _BackChip extends StatelessWidget {
  final VoidCallback onTap;

  const _BackChip({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: c.surface,
          shape: BoxShape.circle,
          border: Border.all(color: c.border),
        ),
        child: Icon(Icons.chevron_left_rounded, size: 19, color: c.textSecondary),
      ),
    );
  }
}

/// Une extrémité du trajet (« Depuis MTN BJ »).
class _RouteEnd extends StatelessWidget {
  final String label;
  final String value;
  final bool alignEnd;

  const _RouteEnd({
    required this.label,
    required this.value,
    this.alignEnd = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: context.text.labelSmall),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.text.titleSmall,
        ),
      ],
    );
  }
}

/// Trois points animés, utilisés pendant les temps d'attente.
class AnimatedDots extends StatefulWidget {
  final Color? color;

  const AnimatedDots({super.key, this.color});

  @override
  State<AnimatedDots> createState() => _AnimatedDotsState();
}

class _AnimatedDotsState extends State<AnimatedDots>
    with SingleTickerProviderStateMixin {
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

  Widget _buildDot(int index) {
    final color = widget.color ?? context.colors.textMuted;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final offset =
            sin((_controller.value * 2 * pi) + (index * pi / 3)) * 2.5;
        return Transform.translate(offset: Offset(0, -offset), child: child);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: CircleAvatar(radius: 3, backgroundColor: color),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 18,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, _buildDot),
      ),
    );
  }
}

/// Champ de numéro avec indicatif figé.
///
/// Le message d'aide change de couleur selon qu'il informe, avertit ou
/// confirme — l'utilisateur sait sans lire si son numéro passe ou non.
class CustomInputFieldWithFixedPrefix extends StatelessWidget {
  final String label;
  final String prefix;
  final TextEditingController controller;
  final Function(String)? onChanged;
  final String? errorText;
  final String? helperText;
  final bool helperIsSuccess;
  final bool helperIsWarning;
  final bool isLoading;
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
    this.isLoading = false,
    this.maxLength,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final helperColor = helperIsSuccess
        ? c.success
        : helperIsWarning
            ? c.warning
            : c.textMuted;

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
      }) =>
          null,
      style: context.text.bodyLarge?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        fontFeatures: kTabularFigures,
      ),
      cursorColor: c.brand,
      keyboardType: TextInputType.phone,
      decoration: InputDecoration(
        labelText: label,
        helperText: helperText,
        helperStyle: context.text.bodySmall?.copyWith(
          color: helperColor,
          fontWeight: helperIsSuccess || helperIsWarning
              ? FontWeight.w600
              : FontWeight.w400,
        ),
        errorText: errorText,
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: AppSpacing.lg, right: AppSpacing.sm),
          child: Text(
            prefix,
            style: context.text.bodyLarge?.copyWith(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: c.textSecondary,
              fontFeatures: kTabularFigures,
            ),
          ),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        suffixIcon: isLoading
            ? Padding(
                padding: const EdgeInsets.all(14),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: c.brand),
                ),
              )
            : helperIsSuccess
                ? Icon(Icons.check_circle_rounded, size: 19, color: c.success)
                : null,
      ),
    );
  }
}
