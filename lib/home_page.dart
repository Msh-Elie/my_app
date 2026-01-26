import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'dart:math';
import 'dart:async'; 
const String BACKEND_BASE = "https://lenticellate-delpha-unaffably.ngrok-free.dev"; 

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  int selectedTab = 0;
  late TabController tabController;

  final List<String> providers = [
    "MTN BJ", "MOOV BJ", "CELTIS BJ", "MOOV BF", "OM BF",
    "MTN CM", "OM CM", "MTN CG", "MTN CI", "MOOV CI",
    "OM CI", "WAVE CI", "MTN GH", "VODAFONE GH", "AIRTEL GH",
    "MTN GN", "OM GN", "AIRTEL KE", "SAFARICOM KE", "OM ML",
    "MOOV ML", "AIRTEL NE", "OM NE", "AIRTEL CD", "OM CD",
    "M-PESA CD", "OM SN", "WAVE SN", "YAS TG", "TOGO TG",
    "MOOV GA", "AIRTEL GA"
  ];

  final Map<String, String> providerPrefixes = {
    "MTN BJ": "+229", "MOOV BJ": "+229", "CELTIS BJ": "+229",
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

  // Nouvelle map pour les devises par pays
  final Map<String, String> countryCurrencies = {
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

  String selectedFrom = "CELTIS BJ";
  String selectedTo = "CELTIS BJ";

  late FixedExtentScrollController fromController;
  late FixedExtentScrollController toController;
  late TextEditingController sendController;
  late TextEditingController receiveController;
  late TextEditingController amountController;

  int stepIndex = 0;

  @override
  void initState() {
    super.initState();

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
  }

  @override
  void dispose() {
    fromController.dispose();
    toController.dispose();
    sendController.dispose();
    receiveController.dispose();
    amountController.dispose();
    tabController.dispose();
    super.dispose();
  }

  // Méthode pour obtenir la devise en fonction du provider sélectionné
  String getCurrencyForProvider(String provider) {
    // Extraire le code pays (les deux derniers caractères)
    String countryCode = provider.length >= 2 
        ? provider.substring(provider.length - 2) 
        : "BJ"; // Valeur par défaut
    
    return countryCurrencies[countryCode] ?? "XOF"; // XOF par défaut
  }

  bool get isContinueActive {
    if (stepIndex == 0) {
      return selectedFrom.isNotEmpty && selectedTo.isNotEmpty;
    } else if (stepIndex == 1) {
      return sendController.text.trim().isNotEmpty && receiveController.text.trim().isNotEmpty;
    } else {
      return amountController.text.trim().isNotEmpty;
    }
  }

  @override
  Widget build(BuildContext context) {
    const double spacingTitleToContent = 0;

    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8, right: 16),
              child: Align(
                alignment: Alignment.topRight,
                child: Icon(
                  Icons.account_circle_outlined,
                  size: 28,
                  color: Colors.white,
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
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      icon: const Icon(
                        Icons.chevron_left,
                        size: 22,
                        color: Colors.white,
                      ),
                      onPressed: () {
                        setState(() {
                          if (stepIndex > 0) stepIndex--;
                        });
                      },
                    ),
                  ),
                  const Center(
                    child: Text(
                      "Transfert",
                      style: TextStyle(
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
              child: LayoutBuilder(
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
              ),
            ),

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

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isContinueActive ? Colors.white : Colors.grey,
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

                child: const Text("Continuer"),
              ),
            ),
            const SizedBox(height: 20),

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
    if (stepIndex == 2) {
      final montant = double.tryParse(amountController.text) ?? 0.0;
      double frais = 0;
      double total = 0;
      
      // Obtenir les devises pour les providers sélectionnés
      String fromCurrency = getCurrencyForProvider(selectedFrom);
      
      // Pour l'instant, on utilise la devise du pays d'origine
      String displayCurrency = fromCurrency;

      if (amountController.text.trim().isNotEmpty) {
        // Tableau de frais adapté aux différentes devises
        if (montant <= 1000) frais = 50;
        else if (montant <= 5000) frais = 100;
        else if (montant <= 10000) frais = 200;
        else if (montant <= 15000) frais = 300;
        else if (montant <= 20000) frais = 400;
        else if (montant <= 25000) frais = 500;
        else if (montant <= 50000) frais = 1000;
        else if (montant <= 75000) frais = 1500;
        else if (montant <= 100000) frais = 2000;
        else if (montant <= 150000) frais = 2500;
        else if (montant <= 200000) frais = 3000;
        else if (montant <= 300000) frais = 4000;
        else frais = 5000;
        total = montant + frais;
      }

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
                    "Montant total : ${total.toStringAsFixed(0)} $displayCurrency",
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
            (from) => setState(() => selectedFrom = from),
            (to) => setState(() => selectedTo = to),
      ),
    )
        : SizedBox(
      key: const ValueKey('inputs'),
      height: 250,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 300,
            child: CustomInputFieldWithFixedPrefix(
              label: "Numéro d'envoi",
              prefix: providerPrefixes[selectedFrom] ?? "+XXX",
              controller: sendController,
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
              onChanged: (_) => setState(() {}),
            ),
          ),
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
  if (stepIndex < 2) {
    final snack = SnackBar(
      duration: const Duration(milliseconds: 900),
      backgroundColor: Colors.white,
      content: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text("Transfert de $selectedFrom vers $selectedTo", style: const TextStyle(color: Colors.black)),
          const SizedBox(width: 8),
          const AnimatedDots(),
        ],
      ),
    );
    scaffold.showSnackBar(snack);
    await Future.delayed(const Duration(milliseconds: 900));
    setStepIndex(stepIndex + 1);
    return;
  }

  // Dernière étape -> lancer transfert complet via backend
  final amountText = amountController.text.trim();
  if (amountText.isEmpty) return;

  final amount = double.tryParse(amountText);
  if (amount == null || amount <= 0) {
    scaffold.showSnackBar(const SnackBar(content: Text("Montant invalide")));
    return;
  }

  // CORRECTION CRITIQUE : S'assurer que les numéros ont le format +229...
  final senderDigits = sendController.text.trim().replaceAll(RegExp(r'[^0-9]'), '');
  final receiverDigits = receiveController.text.trim().replaceAll(RegExp(r'[^0-9]'), '');
  
  final senderMsisdn = providerPrefixes[selectedFrom]! + senderDigits;
  final receiverMsisdn = providerPrefixes[selectedTo]! + receiverDigits;

  // VÉRIFICATION IMPORTANTE
  debugPrint("🔍 Vérification des numéros:");
  debugPrint("📱 Expéditeur: $senderMsisdn (format correct: ${senderMsisdn.startsWith('+')})");
  debugPrint("📱 Destinataire: $receiverMsisdn (format correct: ${receiverMsisdn.startsWith('+')})");

  final body = {
    "amount": amount,
    "senderPhone": senderMsisdn,
    "senderProvider": selectedFrom,
    "receiverPhone": receiverMsisdn,
    "receiverProvider": selectedTo,
  };

  debugPrint("📤 Payload envoyé au backend : ${jsonEncode(body)}");

  const maxRetries = 3;
  int attempt = 0;
  bool success = false;

  while (attempt < maxRetries && !success) {
    attempt++;
    try {
      final response = await http
          .post(
            Uri.parse("$BACKEND_BASE/api/transfer"),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 12));

      final contentType = response.headers['content-type'] ?? '';
      if (contentType.contains('application/json')) {
        final data = jsonDecode(response.body);
        if (response.statusCode == 200) {
          final id = data['depositId'] ?? data['externalId'] ?? "N/A";
          scaffold.showSnackBar(SnackBar(content: Text("✅ Transfert initié : $id"), backgroundColor: Colors.white));
          success = true;
          break;
        } else {
          final err = data['error'] ?? "Erreur ${response.statusCode}";
          scaffold.showSnackBar(SnackBar(content: Text("Erreur backend : $err"), backgroundColor: Color# Réinitialisation complète de Windows Spotlight
Get-AppxPackage -allusers Microsoft.Windows.ContentDeliveryManager | Foreach {
    Add-AppxPackage -DisableDevelopmentMode -Register "$($_.InstallLocation)\AppXManifest.xml"
}

# Supprimer les fichiers de configuration Spotlight
Remove-Item "$env:LOCALAPPDATA\Packages\Microsoft.Windows.ContentDeliveryManager_cw5n1h2txyewy\Settings\settings.dat" -Force -ErrorAction SilentlyContinue
Remove-Item "$env:LOCALAPPDATA\Packages\Microsoft.Windows.ContentDeliveryManager_cw5n1h2txyewy\Settings\roaming.lock" -Force -ErrorAction SilentlyContinue

# Redémarrer Explorer pour appliquer
Stop-Process -Name explorer -Force
Start-Process explorer


              s.red));
          break;
        }
      } else {
        debugPrint("⚠️ Réponse inattendue: ${response.body}");
        scaffold.showSnackBar(SnackBar(content: Text("Erreur backend : réponse inattendue (${response.statusCode})"), backgroundColor: Colors.red));
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
                  onSelectedItemChanged: (index) => onFromChanged(providers[index]),
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
                  onSelectedItemChanged: (index) => onToChanged(providers[index]),
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

  const CustomInputFieldWithFixedPrefix({
    required this.label,
    required this.prefix,
    required this.controller,
    this.onChanged,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
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