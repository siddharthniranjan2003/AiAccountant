import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../core/palette.dart';
import '../core/constants.dart';

/// Vertical navigation rail used on wide (desktop) layouts. Mirrors the visual
/// language of [AppBottomNav] — circular ink-bordered icons, the camera entry
/// (index 2) rendered as an accented action rather than a destination — but laid
/// out as a left-hand column instead of a bottom row.
class AppSideNav extends StatelessWidget {
  const AppSideNav({
    super.key,
    required this.currentIndex,
    required this.onSelected,
  });

  final int currentIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: kSideNavWidth,
      decoration: BoxDecoration(
        color: AppPalette.paper.withValues(alpha: 0.92),
        border: const Border(
          right: BorderSide(color: AppPalette.ink, width: 1.5),
        ),
      ),
      child: SafeArea(
        right: false,
        child: Column(
          children: [
            const SizedBox(height: 12),
            for (int index = 0; index < bottomNavItems.length; index++)
              // The Camera entry (document scanner) is Android-only; hide it on
              // web while keeping the index mapping intact for the other tabs.
              if (!(kIsWeb && index == 2))
                _SideNavItem(
                  index: index,
                  selected: index == currentIndex,
                  onTap: () => onSelected(index),
                ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

class _SideNavItem extends StatelessWidget {
  const _SideNavItem({
    required this.index,
    required this.selected,
    required this.onTap,
  });

  final int index;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isCamera = index == 2;
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 72,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Selected indicator — a vertical bar on the left edge (the rail's
            // analogue of the bottom nav's top underline). Never for the camera.
            if (selected && !isCamera)
              Positioned(
                left: 0,
                top: 16,
                bottom: 16,
                child: Container(
                  width: 3,
                  decoration: BoxDecoration(
                    color: AppPalette.ink,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  width: isCamera ? 50 : 40,
                  height: isCamera ? 50 : 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isCamera
                        ? selected
                            ? AppPalette.accent
                            : AppPalette.sheet
                        : selected
                            ? AppPalette.accent2.withValues(alpha: 0.45)
                            : Colors.transparent,
                    border: Border.all(
                      color: AppPalette.ink,
                      width: isCamera ? 1.7 : 1.4,
                    ),
                  ),
                  child: Icon(
                    bottomNavItems[index].icon,
                    size: isCamera ? 26 : 20,
                    color: isCamera && selected ? Colors.white : AppPalette.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  bottomNavItems[index].label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: selected ? AppPalette.ink : AppPalette.inkSoft,
                        fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                      ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
