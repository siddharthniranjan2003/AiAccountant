import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/palette.dart';

class SuccessScreen extends StatefulWidget {
  const SuccessScreen({super.key});

  @override
  State<SuccessScreen> createState() => _SuccessScreenState();
}

class _SuccessScreenState extends State<SuccessScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _progress;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _progress = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.linear),
    );
    _ctrl.forward();
    _ctrl.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        // Sign-in has flipped the auth stream, so the gate route (`/` in
        // main.dart) now renders the Shell. Pop the Success/OTP/Login routes
        // back to it instead of pushing a new Shell — this keeps the reactive
        // gate as the single base route, so back exits the app and cold-start
        // persistence stays intact.
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.paper,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Transform.rotate(
                angle: 0.07,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppPalette.success, width: 3),
                    color: AppPalette.success.withValues(alpha: 0.07),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.check_rounded,
                    size: 42,
                    color: AppPalette.success,
                  ),
                ),
              ),
              const SizedBox(height: 26),
              Text(
                "you're in!",
                style: GoogleFonts.caveat(
                  fontSize: 40,
                  fontWeight: FontWeight.w700,
                  color: AppPalette.ink,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'opening your queue · your AI accountant is ready to go.',
                textAlign: TextAlign.center,
                style: GoogleFonts.kalam(
                  fontSize: 14,
                  color: AppPalette.inkSoft,
                  height: 1.55,
                ),
              ),
              const SizedBox(height: 36),
              SizedBox(
                width: MediaQuery.of(context).size.width * 0.8,
                height: 4,
                child: AnimatedBuilder(
                  animation: _progress,
                  builder: (_, _) => LinearProgressIndicator(
                    value: _progress.value,
                    backgroundColor: AppPalette.ink.withValues(alpha: 0.12),
                    valueColor:
                        const AlwaysStoppedAnimation(AppPalette.ink),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'redirecting…',
                style: GoogleFonts.architectsDaughter(
                  fontSize: 12,
                  color: AppPalette.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
