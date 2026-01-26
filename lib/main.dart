import 'package:flutter/material.dart';
import 'home_page.dart'; // ta page principale

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(), // thème sombre
      home: const HomePage(),   // <-- démarre directement sur HomePage
    );
  }
}
