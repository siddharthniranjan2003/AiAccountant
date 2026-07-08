import 'package:flutter/material.dart';
import '../../core/palette.dart';

class ProfileHeaderCard extends StatelessWidget {
  const ProfileHeaderCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppPalette.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: AppPalette.cardBorder, width: AppPalette.cardBorderWidth),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppPalette.accent2.withValues(alpha: 0.4),
              border: Border.all(
                  color: AppPalette.cardBorder,
                  width: AppPalette.cardBorderWidth),
            ),
            child: Text('KV', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('K V Enterprises', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text('kventerprises.fbd@gmail.com · GST 06ALQPB8309N1ZO', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppPalette.inkSoft)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SettingRow extends StatelessWidget {
  const SettingRow({
    super.key,
    required this.label,
    this.destructive = false,
    this.onTap,
  });

  final String label;
  final bool destructive;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: AppPalette.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: destructive ? AppPalette.accent : AppPalette.cardBorder,
              width: AppPalette.cardBorderWidth),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: destructive ? AppPalette.accent : AppPalette.ink,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: destructive ? AppPalette.accent : AppPalette.inkSoft),
          ],
        ),
      ),
    );
  }
}
