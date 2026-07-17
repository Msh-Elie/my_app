import 'package:flutter/material.dart';

class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Aide'), backgroundColor: Colors.black),
      backgroundColor: Colors.black,
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text('Aide', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
            SizedBox(height: 16),
            Text('• Comment envoyer un transfert', style: TextStyle(color: Colors.white70)),
            SizedBox(height: 8),
            Text('• Vérifier le statut', style: TextStyle(color: Colors.white70)),
            SizedBox(height: 8),
            Text('• Contact support: support@switchmoney.com', style: TextStyle(color: Colors.white70)),
          ],
        ),
      ),
    );
  }
}
