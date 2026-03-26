import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'screens/request_payment_screen.dart';

void main() {
  runApp(const ProviderScope(child: DarajaApp()));
}

class DarajaApp extends StatelessWidget {
  const DarajaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'flutter-daraja-raw',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      home: const RequestPaymentScreen(),
    );
  }
}
