import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../widgets/screen_frame.dart';
import '../widgets/profile_header_card.dart';
import 'splash_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    super.key,
    required this.currentIndex,
    required this.onNavSelected,
  });

  final int currentIndex;
  final ValueChanged<int> onNavSelected;

  Future<void> _signOut(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const SplashScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ScreenFrame(
      currentIndex: currentIndex,
      onNavSelected: onNavSelected,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 16),
        children: [
          const ProfileHeaderCard(),
          const SizedBox(height: 14),
          const SettingRow(label: 'Business details'),
          const SizedBox(height: 6),
          const SettingRow(label: 'Tax / GST settings'),
          const SizedBox(height: 6),
          const SettingRow(label: 'Currency & date'),
          const SizedBox(height: 6),
          const SettingRow(label: 'Backup & export'),
          const SizedBox(height: 6),
          const SettingRow(label: 'AI accuracy'),
          const SizedBox(height: 6),
          const SettingRow(label: 'Help & support'),
          const SizedBox(height: 6),
          SettingRow(
            label: 'Sign out',
            destructive: true,
            onTap: () => _signOut(context),
          ),
        ],
      ),
    );
  }
}
