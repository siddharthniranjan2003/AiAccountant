import 'package:flutter/material.dart';
import 'models.dart';

const double kBottomNavHeight = 78;
const double kBulkBarHeight = 58;

// At or above this width the shell switches from the phone card + bottom nav to
// a full-width desktop layout with a left navigation rail.
const double kDesktopBreakpoint = 900;
const double kSideNavWidth = 96;

// On desktop, auth forms (login/OTP) center at this width instead of stretching
// edge-to-edge. Modal sheets use the bottom-sheet cap in the theme.
const double kFormMaxWidth = 440;

const List<BottomNavItemData> bottomNavItems = [
  BottomNavItemData(label: 'Queue', icon: Icons.view_agenda_rounded),
  BottomNavItemData(label: 'History', icon: Icons.history_rounded),
  BottomNavItemData(label: 'Camera', icon: Icons.camera_alt_rounded),
  // Report temporarily hidden. This list is positionally aligned with the
  // IndexedStack children in app_shell.dart — uncommenting here REQUIRES
  // uncommenting ReportScreen there, or every index below it shifts.
  // BottomNavItemData(
  //     label: 'Report', icon: Icons.insert_chart_outlined_rounded),
  BottomNavItemData(label: 'Profile', icon: Icons.person_outline_rounded),
];

const List<Color> capturePalette = [
  Color(0xFFD94F3A),
  Color(0xFFF2C94C),
  Color(0xFF7FA6F6),
  Color(0xFF55A780),
  Color(0xFFCA7C57),
];
