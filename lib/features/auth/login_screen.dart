import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants.dart';
import '../../core/palette.dart';
import '../../data/session_store.dart';
import '../../shared/responsive.dart';
import 'otp_screen.dart';
import 'success_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneCtrl = TextEditingController();
  bool _loading = false;
  String? _error;
  // Token from the previous codeSent; passed on subsequent sends so Firebase
  // treats a repeat request as an explicit resend and re-fires codeSent.
  int? _resendToken;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  void _sendOtp() {
    if (_loading) return;
    _doSendOtp();
  }

  Future<void> _doSendOtp() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.length < 10) {
      setState(() => _error = 'Enter a valid 10-digit number');
      return;
    }
    setState(() { _loading = true; _error = null; });
    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: '+91$phone',
      forceResendingToken: _resendToken,
      verificationCompleted: (PhoneAuthCredential credential) async {
        try {
          await FirebaseAuth.instance.signInWithCredential(credential);
          await SessionStore.savePhone(phone);
          if (mounted) _goToSuccess();
        } catch (_) {
          if (mounted) setState(() { _loading = false; _error = 'Auto-verification failed'; });
        }
      },
      verificationFailed: (FirebaseAuthException e) {
        if (mounted) setState(() { _loading = false; _error = e.message ?? 'Verification failed'; });
      },
      codeSent: (String verificationId, int? resendToken) {
        _resendToken = resendToken;
        if (!mounted) return;
        setState(() => _loading = false);
        Navigator.of(context).push(
          PageRouteBuilder(
            pageBuilder: (_, _, _) => OtpScreen(phone: phone, verificationId: verificationId),
            transitionsBuilder: (_, anim, _, child) => SlideTransition(
              position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
                  .animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
              child: child,
            ),
            transitionDuration: const Duration(milliseconds: 300),
          ),
        );
      },
      codeAutoRetrievalTimeout: (_) {},
    );
  }

  void _goToSuccess() {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, _, _) => const SuccessScreen(),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.paper,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: context.isWideScreen ? constraints.maxHeight : 0,
            ),
            child: ResponsiveCenter(
            maxWidth: kFormMaxWidth,
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 40),
              _BrandBlock(),
              const SizedBox(height: 28),
              _PhonePane(
                phoneCtrl: _phoneCtrl,
                onSendOtp: _sendOtp,
                loading: _loading,
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppPalette.accent.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: AppPalette.accent.withValues(alpha: 0.3)),
                  ),
                  child: Text(_error!, style: GoogleFonts.kalam(fontSize: 12, color: AppPalette.accent)),
                ),
              ],
              if (_loading) ...[
                const SizedBox(height: 10),
                const LinearProgressIndicator(),
              ],
              const SizedBox(height: 32),
            ],
          ),
          ),
          ),
          ),
        ),
      ),
    );
  }
}

class _BrandBlock extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Transform.rotate(
          angle: -0.08,
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppPalette.ink,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [BoxShadow(color: AppPalette.accent.withValues(alpha: 0.45), offset: const Offset(3, 3), blurRadius: 0)],
            ),
            alignment: Alignment.center,
            child: Text('A', style: GoogleFonts.caveat(fontSize: 22, fontWeight: FontWeight.w700, color: AppPalette.paper)),
          ),
        ),
        const SizedBox(width: 12),
        Text('Welcome back', style: GoogleFonts.caveat(fontSize: 24, fontWeight: FontWeight.w700, color: AppPalette.ink)),
      ],
    );
  }
}

class _AuthField extends StatelessWidget {
  final String label;
  final String placeholder;
  final TextEditingController controller;
  final Widget? prefix;
  final TextInputType? keyboardType;
  final String? hint;

  const _AuthField({
    required this.label,
    required this.placeholder,
    required this.controller,
    this.prefix,
    this.keyboardType,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.architectsDaughter(fontSize: 11, fontStyle: FontStyle.italic, color: AppPalette.inkSoft)),
        const SizedBox(height: 4),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: AppPalette.ink, width: 1.5),
            color: Colors.white.withValues(alpha: 0.45),
          ),
          child: Row(
            children: [
              ?prefix,
              Expanded(
                child: TextField(
                  controller: controller,
                  keyboardType: keyboardType,
                  style: GoogleFonts.jetBrainsMono(fontSize: 13, color: AppPalette.ink),
                  decoration: InputDecoration(
                    hintText: placeholder,
                    hintStyle: GoogleFonts.jetBrainsMono(fontSize: 13, color: AppPalette.muted),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (hint != null) ...[
          const SizedBox(height: 4),
          Text(hint!, style: GoogleFonts.architectsDaughter(fontSize: 11, color: AppPalette.muted)),
        ],
      ],
    );
  }
}

class _AuthButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool alt;
  final bool enabled;
  const _AuthButton({required this.label, required this.onTap, this.alt = false, this.enabled = true});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: enabled ? (alt ? AppPalette.accent : AppPalette.ink) : AppPalette.muted,
          borderRadius: BorderRadius.circular(10),
          boxShadow: enabled
              ? [BoxShadow(color: alt ? AppPalette.ink : AppPalette.accent, offset: const Offset(3, 3), blurRadius: 0)]
              : null,
        ),
        child: Text(label, style: GoogleFonts.kalam(fontSize: 15, fontWeight: FontWeight.w700, color: AppPalette.paper)),
      ),
    );
  }
}

class _PhonePane extends StatelessWidget {
  final TextEditingController phoneCtrl;
  final VoidCallback onSendOtp;
  final bool loading;

  const _PhonePane({
    required this.phoneCtrl,
    required this.onSendOtp,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AuthField(
          label: 'phone number',
          placeholder: '98xxx xxxxx',
          controller: phoneCtrl,
          keyboardType: TextInputType.phone,
          hint: "we'll text a 6-digit code",
          prefix: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
            decoration: const BoxDecoration(border: Border(right: BorderSide(color: AppPalette.ink, width: 1.5))),
            child: Text('+91', style: GoogleFonts.jetBrainsMono(fontSize: 13, color: AppPalette.inkSoft)),
          ),
        ),
        const SizedBox(height: 18),
        _AuthButton(label: 'Send OTP →', onTap: onSendOtp, alt: true, enabled: !loading),
      ],
    );
  }
}

