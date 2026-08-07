import 'package:flutter/material.dart';
import '../shared/stock_cube_icon.dart';
import 'models.dart';
import 'site_config.dart';

const double kBottomNavHeight = 78;
const double kBulkBarHeight = 58;

// At or above this width the shell switches from the phone card + bottom nav to
// a full-width desktop layout with a left navigation rail.
const double kDesktopBreakpoint = 900;
const double kSideNavWidth = 96;

// On desktop, auth forms (login/OTP) center at this width instead of stretching
// edge-to-edge. Modal sheets use the bottom-sheet cap in the theme.
const double kFormMaxWidth = 440;

// How each destination draws in the nav. Which of them a build actually shows,
// and in what order, is SiteConfig's business — this map only says what an
// entry looks like.
//
// Camera is an ACTION, not a destination: tapping it opens the document scanner
// and never becomes the selected index (see app_shell's _onNavSelected). It
// still gets an entry so it can sit in the bar like its neighbours.
const Map<AppDestination, BottomNavItemData> navItemFor = {
  AppDestination.camera:
      BottomNavItemData(label: 'Camera', icon: Icons.camera_alt_rounded),
  AppDestination.queue:
      BottomNavItemData(label: 'Queue', icon: Icons.view_agenda_rounded),
  AppDestination.history:
      BottomNavItemData(label: 'History', icon: Icons.history_rounded),
  AppDestination.report: BottomNavItemData(
      label: 'Report', icon: Icons.insert_chart_outlined_rounded),
  AppDestination.profile:
      BottomNavItemData(label: 'Profile', icon: Icons.person_outline_rounded),
  AppDestination.rate:
      BottomNavItemData(label: 'Rate', iconBuilder: buildStockCubeNavIcon),
};

/// Top-level so [navItemFor] can stay const (a tear-off of a top-level function
/// is a constant; a closure is not).
Widget buildStockCubeNavIcon(double size, Color color) =>
    StockCubeIcon(size: size, color: color);

const List<Color> capturePalette = [
  Color(0xFFD94F3A),
  Color(0xFFF2C94C),
  Color(0xFF7FA6F6),
  Color(0xFF55A780),
  Color(0xFFCA7C57),
];
