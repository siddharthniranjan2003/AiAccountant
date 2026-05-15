import 'package:flutter/material.dart';
import '../core/palette.dart';

class AppTopTabs extends StatelessWidget {
  const AppTopTabs({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppPalette.ink, width: 1.3),
        ),
      ),
      child: Row(
        children: [
          for (int index = 0; index < labels.length; index++)
            Expanded(
              child: InkWell(
                onTap: () => onSelected(index),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(
                      right: index == labels.length - 1
                          ? BorderSide.none
                          : const BorderSide(
                              color: AppPalette.ink,
                              width: 1.2,
                            ),
                    ),
                  ),
                  padding: const EdgeInsets.only(top: 12, bottom: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        labels[index],
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: index == selectedIndex
                                  ? AppPalette.ink
                                  : AppPalette.inkSoft,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 8),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOut,
                        width: index == selectedIndex ? 56 : 24,
                        height: 3,
                        decoration: BoxDecoration(
                          color: index == selectedIndex
                              ? AppPalette.ink
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
