import 'package:flutter/material.dart';
import '../../core/palette.dart';

class ProfileHeaderCard extends StatelessWidget {
  const ProfileHeaderCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppPalette.ink, width: 1.4),
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
              border: Border.all(color: AppPalette.ink, width: 1.4),
            ),
            child: Text('RK', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Ravi Kumar', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text('ravi@store.in · GST 27ABCDE1234F1Z5', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppPalette.inkSoft)),
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
          color: Colors.white.withValues(alpha: 0.62),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: destructive ? AppPalette.accent : AppPalette.ink, width: 1.4),
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
