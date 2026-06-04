import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'features/shell/app_shell.dart';
import 'features/auth/splash_screen.dart';
import 'core/theme.dart';
import 'data/stock_items_cache.dart';
import 'data/customers_cache.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_SERVICE_KEY']!,
  );
  runApp(const AccountantApp());
  StockItemsCache.instance.fetch();
  CustomersCache.instance.fetch();
}

class AccountantApp extends StatelessWidget {
  const AccountantApp({super.key});

  static final _scaffoldKey = GlobalKey<ScaffoldMessengerState>();

  @override
  Widget build(BuildContext context) {
    StockItemsCache.scaffoldKey = _scaffoldKey;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AI Accountant',
      theme: buildAppTheme(),
      scaffoldMessengerKey: _scaffoldKey,
      home: FirebaseAuth.instance.currentUser != null
          ? const AccountantShell()
          : const SplashScreen(),
    );
  }
}
