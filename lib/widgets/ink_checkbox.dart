import 'package:flutter/material.dart';
import '../core/palette.dart';

class InkCheckbox extends StatelessWidget {
  const InkCheckbox({
    super.key,
    required this.value,
    required this.success,
    required this.processing,
    this.onTap,
  });

  final bool value;
  final bool success;
  final bool processing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: success
              ? AppPalette.success.withOpacity(0.16)
              : value
                  ? AppPalette.accent2.withOpacity(0.26)
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: success
                ? AppPalette.success
                : value
                    ? AppPalette.accent
                    : AppPalette.ink,
            width: 1.4,
          ),
        ),
        alignment: Alignment.center,
        child: processing
            ? const SizedBox(
                width: 9,
                height: 9,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: AppPalette.accent,
                ),
              )
            : value
                ? Icon(
                    Icons.check_rounded,
                    size: 12,
                    color: success ? AppPalette.success : AppPalette.accent,
                  )
                : null,
      ),
    );
  }
}
