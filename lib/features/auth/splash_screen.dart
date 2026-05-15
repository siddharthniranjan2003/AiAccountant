import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/palette.dart';
import 'login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _ctrl.forward();
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, _, _) => const LoginScreen(),
          transitionsBuilder: (_, anim, _, child) =>
              FadeTransition(opacity: anim, child: child),
          transitionDuration: const Duration(milliseconds: 400),
        ),
      );
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
      body: FadeTransition(
        opacity: _fade,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Transform.rotate(
                angle: -0.10,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppPalette.ink,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: AppPalette.accent.withValues(alpha: 0.55),
                        offset: const Offset(5, 5),
                        blurRadius: 0,
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'A',
                    style: GoogleFonts.caveat(
                      fontSize: 44,
                      fontWeight: FontWeight.w700,
                      color: AppPalette.paper,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              RichText(
                text: TextSpan(
                  style: GoogleFonts.caveat(
                    fontSize: 34,
                    fontWeight: FontWeight.w700,
                    color: AppPalette.ink,
                  ),
                  children: [
                    const TextSpan(text: 'Accountant'),
                    TextSpan(
                      text: '·',
                      style: GoogleFonts.caveat(
                        fontSize: 34,
                        fontWeight: FontWeight.w700,
                        color: AppPalette.accent,
                      ),
                    ),
                    const TextSpan(text: 'AI'),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'your books, on autopilot',
                style: GoogleFonts.architectsDaughter(
                  fontSize: 14,
                  color: AppPalette.inkSoft,
                ),
              ),
              const SizedBox(height: 64),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _Dot(active: true),
                  const SizedBox(width: 6),
                  _Dot(active: false),
                  const SizedBox(width: 6),
                  _Dot(active: false),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final bool active;
  const _Dot({required this.active});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 4,
      decoration: BoxDecoration(
        color: active
            ? AppPalette.ink
            : AppPalette.ink.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}
