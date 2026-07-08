import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../core/palette.dart';
import '../core/constants.dart';

class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.currentIndex,
    required this.onSelected,
  });

  final int currentIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
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
          for (int index = 0; index < bottomNavItems.length; index++)
            // The Camera entry (document scanner) is Android-only; hide it on
            // web while keeping the index mapping intact for the other tabs.
            if (!(kIsWeb && index == 2))
            Expanded(
              child: InkWell(
                onTap: () => onSelected(index),
                child: Stack(
                  alignment: Alignment.topCenter,
                  children: [
                    if (index == currentIndex && index != 2)
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
                          Transform.translate(
                            offset: Offset(0, index == 2 ? -18 : 0),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              curve: Curves.easeOut,
                              width: index == 2 ? 52 : 40,
                              height: index == 2 ? 52 : 40,
                              margin: EdgeInsets.only(
                                bottom: index == 2 ? 5 : 2,
                              ),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: index == 2
                                    ? currentIndex == index
                                        ? AppPalette.accent
                                        : AppPalette.sheet
                                    : currentIndex == index
                                        ? AppPalette.accent2.withValues(alpha: 0.45)
                                        : Colors.transparent,
                                border: Border.all(
                                  color: AppPalette.ink,
                                  width: index == 2 ? 1.7 : 1.4,
                                ),
                              ),
                              child: Icon(
                                bottomNavItems[index].icon,
                                size: index == 2 ? 26 : 20,
                                color: index == 2 && currentIndex == index
                                    ? Colors.white
                                    : AppPalette.ink,
                              ),
                            ),
                          ),
                          Text(
                            bottomNavItems[index].label,
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
