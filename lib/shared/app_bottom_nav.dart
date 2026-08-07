import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../core/palette.dart';
import '../core/constants.dart';
import '../core/site_config.dart';

class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.currentIndex,
    required this.onSelected,
    this.site,
  });

  final int currentIndex;
  final ValueChanged<int> onSelected;

  /// Test seam. [SiteConfig.current] is a compile-time define, so a test process
  /// can't vary it; production never passes this.
  final SiteConfig? site;

  @override
  Widget build(BuildContext context) {
    final destinations = (site ?? SiteConfig.current).destinations;
    return Container(
      height: kBottomNavHeight,
      decoration: BoxDecoration(
        color: AppPalette.paper.withValues(alpha: 0.92),
        border: const Border(
          top: BorderSide(color: AppPalette.ink, width: 1.5),
        ),
      ),
      child: Row(
        children: [
          for (int index = 0; index < destinations.length; index++)
            // The Camera entry (document scanner) is Android-only; hide it on
            // web while keeping the index mapping intact for the other tabs.
            if (!(kIsWeb && destinations[index] == AppDestination.camera))
            Expanded(
              child: InkWell(
                onTap: () => onSelected(index),
                child: Stack(
                  alignment: Alignment.topCenter,
                  children: [
                    if (index == currentIndex)
                      Positioned(
                        top: 0,
                        left: 22,
                        right: 22,
                        child: Container(
                          height: 3,
                          decoration: BoxDecoration(
                            color: AppPalette.ink,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Every tab draws the same: Camera used to be a raised,
                          // accent-filled 52px circle sitting proud of the bar.
                          // It now reads as an ordinary destination even though
                          // tapping it opens the scanner.
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOut,
                            width: 40,
                            height: 40,
                            margin: const EdgeInsets.only(bottom: 2),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: currentIndex == index
                                  ? AppPalette.accent2.withValues(alpha: 0.45)
                                  : Colors.transparent,
                              border: Border.all(
                                color: AppPalette.ink,
                                width: 1.4,
                              ),
                            ),
                            child: navItemFor[destinations[index]]!
                                .buildIcon(20, AppPalette.ink),
                          ),
                          Text(
                            navItemFor[destinations[index]]!.label,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: currentIndex == index
                                      ? AppPalette.ink
                                      : AppPalette.inkSoft,
                                  fontWeight: currentIndex == index
                                      ? FontWeight.w800
                                      : FontWeight.w700,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
