import 'package:flutter/material.dart';
import '../core/palette.dart';
import '../core/models.dart';

class ToastStack extends StatelessWidget {
  const ToastStack({
    super.key,
    required this.toasts,
  });

  final List<ToastEntry> toasts;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final toast in toasts) ...[
          ToastCard(toast: toast),
          const SizedBox(height: 6),
        ],
      ],
    );
  }
}

class ToastCard extends StatelessWidget {
  const ToastCard({
    super.key,
    required this.toast,
  });

  final ToastEntry toast;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = switch (toast.kind) {
      ToastKind.processing => AppPalette.ink,
      ToastKind.success => AppPalette.success,
      ToastKind.info => AppPalette.pen,
    };

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(
              color: Color(0x24000000),
              blurRadius: 8,
              offset: Offset(2, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            if (toast.kind == ToastKind.processing)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 1.8,
                  color: Colors.white,
                ),
              )
            else
              const Icon(
                Icons.check_circle_rounded,
                size: 16,
                color: Colors.white,
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                toast.message,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.white,
                      fontSize: 12,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
