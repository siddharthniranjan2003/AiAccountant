import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../core/palette.dart';
import '../core/constants.dart';
import '../core/site_config.dart';

/// Vertical navigation rail used on wide (desktop) layouts. Circular
/// ink-bordered icons laid out as a left-hand column instead of a bottom row.
/// Unlike [AppBottomNav], which now draws every entry the same, the rail still
/// renders the camera as a larger accented action to mark it as a thing you do
/// rather than a place you go.
class AppSideNav extends StatelessWidget {
  const AppSideNav({
    super.key,
    required this.currentIndex,
    required this.onSelected,
    this.site,
  });

  final int currentIndex;
  final ValueChanged<int> onSelected;

  /// Test seam — see [AppBottomNav.site].
  final SiteConfig? site;

  Widget _item(int index, AppDestination destination) => _SideNavItem(
        destination: destination,
        selected: index == currentIndex,
        onTap: () => onSelected(index),
      );

  @override
  Widget build(BuildContext context) {
    final destinations = (site ?? SiteConfig.current).destinations;
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
            // Same order as the bottom bar — the site's destination list is the
            // single source of nav order. The Camera entry (document scanner)
            // is Android-only; hidden on web.
            for (int index = 0; index < destinations.length; index++)
              if (!(kIsWeb && destinations[index] == AppDestination.camera))
                _item(index, destinations[index]),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

class _SideNavItem extends StatelessWidget {
  const _SideNavItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final AppDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final item = navItemFor[destination]!;
    final isCamera = destination == AppDestination.camera;
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
                  child: item.buildIcon(
                    isCamera ? 26 : 20,
                    isCamera && selected ? Colors.white : AppPalette.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.label,
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
