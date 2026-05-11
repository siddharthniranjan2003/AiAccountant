import 'package:flutter/material.dart';

import 'core/theme.dart';
import 'screens/splash_screen.dart';

void main() {
  runApp(const AccountantApp());
}

class AccountantApp extends StatelessWidget {
  const AccountantApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AI Accountant',
      theme: buildAppTheme(),
      home: const SplashScreen(),
    );
  }
}
