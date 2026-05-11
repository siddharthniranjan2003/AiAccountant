import 'package:flutter/material.dart';
import '../widgets/screen_frame.dart';
import '../widgets/profile_header_card.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    super.key,
    required this.currentIndex,
    required this.onNavSelected,
  });

  final int currentIndex;
  final ValueChanged<int> onNavSelected;

  @override
  Widget build(BuildContext context) {
    return ScreenFrame(
      currentIndex: currentIndex,
      onNavSelected: onNavSelected,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 16),
        children: const [
          ProfileHeaderCard(),
          SizedBox(height: 14),
          SettingRow(label: 'Business details'),
          SizedBox(height: 6),
          SettingRow(label: 'Tax / GST settings'),
          SizedBox(height: 6),
          SettingRow(label: 'Currency & date'),
          SizedBox(height: 6),
          SettingRow(label: 'Backup & export'),
          SizedBox(height: 6),
          SettingRow(label: 'AI accuracy'),
          SizedBox(height: 6),
          SettingRow(label: 'Help & support'),
          SizedBox(height: 6),
          SettingRow(label: 'Sign out', destructive: true),
        ],
      ),
    );
  }
}
