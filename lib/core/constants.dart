import 'package:flutter/material.dart';
import 'models.dart';

const double kBottomNavHeight = 78;
const double kBulkBarHeight = 58;

const List<BottomNavItemData> bottomNavItems = [
  BottomNavItemData(label: 'Queue', icon: Icons.view_agenda_rounded),
  BottomNavItemData(label: 'History', icon: Icons.history_rounded),
  BottomNavItemData(label: 'Camera', icon: Icons.camera_alt_rounded),
  BottomNavItemData(
      label: 'Report', icon: Icons.insert_chart_outlined_rounded),
  BottomNavItemData(label: 'Profile', icon: Icons.person_outline_rounded),
];

const List<Color> capturePalette = [
  Color(0xFFD94F3A),
  Color(0xFFF2C94C),
  Color(0xFF7FA6F6),
  Color(0xFF55A780),
  Color(0xFFCA7C57),
];
