import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/palette.dart';
import 'otp_screen.dart';
import 'success_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  int _mode = 0;

  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _passVisible = false;
  bool _rememberMe = true;

  final _phoneCtrl = TextEditingController();
  bool _whatsappOk = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  void _signInWithEmail() {
    if (_loading) return;
    _doSignInWithEmail();
  }

  Future<void> _doSignInWithEmail() async {
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;
    if (email.isEmpty || pass.isEmpty) {
      setState(() => _error = 'Enter email and password');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: pass);
      if (mounted) _goToSuccess();
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() { _loading = false; _error = _friendlyError(e.code); });
    }
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
      verificationCompleted: (PhoneAuthCredential credential) async {
        try {
          await FirebaseAuth.instance.signInWithCredential(credential);
          if (mounted) _goToSuccess();
        } catch (_) {
          if (mounted) setState(() { _loading = false; _error = 'Auto-verification failed'; });
        }
      },
      verificationFailed: (FirebaseAuthException e) {
        if (mounted) setState(() { _loading = false; _error = e.message ?? 'Verification failed'; });
      },
      codeSent: (String verificationId, int? resendToken) {
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
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, _, _) => const SuccessScreen(),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  String _friendlyError(String code) {
    switch (code) {
      case 'user-not-found': return 'No account found for this email';
      case 'wrong-password': return 'Incorrect password';
      case 'invalid-email': return 'Invalid email address';
      case 'invalid-credential': return 'Incorrect email or password';
      case 'user-disabled': return 'This account has been disabled';
      case 'too-many-requests': return 'Too many attempts. Try later';
      default: return 'Sign in failed. Try again';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.paper,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 40),
              _BrandBlock(),
              const SizedBox(height: 28),
              _SegmentedSlider(
                selected: _mode,
                onChanged: (v) => setState(() => _mode = v),
              ),
              const SizedBox(height: 22),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: _mode == 0
                    ? _EmailPane(
                        key: const ValueKey('email'),
                        emailCtrl: _emailCtrl,
                        passCtrl: _passCtrl,
                        passVisible: _passVisible,
                        onPassToggle: () => setState(() => _passVisible = !_passVisible),
                        rememberMe: _rememberMe,
                        onRememberMe: (v) => setState(() => _rememberMe = v ?? true),
                        onSignIn: _signInWithEmail,
                      )
                    : _PhonePane(
                        key: const ValueKey('phone'),
                        phoneCtrl: _phoneCtrl,
                        whatsappOk: _whatsappOk,
                        onWhatsapp: (v) => setState(() => _whatsappOk = v ?? true),
                        onSendOtp: _sendOtp,
                      ),
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
              const SizedBox(height: 28),
              Row(
                children: [
                  const Expanded(child: Divider(color: AppPalette.ink, thickness: 1)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'or continue with',
                      style: GoogleFonts.architectsDaughter(fontSize: 12, color: AppPalette.muted),
                    ),
                  ),
                  const Expanded(child: Divider(color: AppPalette.ink, thickness: 1)),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: _SocialButton(label: 'G · Google')),
                  const SizedBox(width: 10),
                  Expanded(child: _SocialButton(label: '⌘ · Apple')),
                ],
              ),
              const SizedBox(height: 28),
              Center(
                child: GestureDetector(
                  onTap: () {},
                  child: Text(
                    'new here? create account',
                    style: GoogleFonts.kalam(
                      fontSize: 13,
                      color: AppPalette.pen,
                      decoration: TextDecoration.underline,
                      decorationColor: AppPalette.pen,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
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

class _SegmentedSlider extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onChanged;
  const _SegmentedSlider({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppPalette.ink, width: 1.5),
      ),
      padding: const EdgeInsets.all(3),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: const Duration(milliseconds: 280),
            curve: const Cubic(0.2, 0.8, 0.2, 1),
            alignment: selected == 0 ? Alignment.centerLeft : Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: 0.5,
              child: Container(decoration: BoxDecoration(color: AppPalette.ink, borderRadius: BorderRadius.circular(18))),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => onChanged(0),
                  behavior: HitTestBehavior.opaque,
                  child: Center(child: Text('Email', style: GoogleFonts.kalam(fontSize: 14, fontWeight: FontWeight.w700, color: selected == 0 ? AppPalette.paper : AppPalette.ink))),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () => onChanged(1),
                  behavior: HitTestBehavior.opaque,
                  child: Center(child: Text('Phone', style: GoogleFonts.kalam(fontSize: 14, fontWeight: FontWeight.w700, color: selected == 1 ? AppPalette.paper : AppPalette.ink))),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AuthField extends StatelessWidget {
  final String label;
  final String placeholder;
  final TextEditingController controller;
  final bool obscure;
  final Widget? suffix;
  final Widget? prefix;
  final TextInputType? keyboardType;
  final String? hint;

  const _AuthField({
    required this.label,
    required this.placeholder,
    required this.controller,
    this.obscure = false,
    this.suffix,
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
                  obscureText: obscure,
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
              ?suffix,
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
  const _AuthButton({required this.label, required this.onTap, this.alt = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: alt ? AppPalette.accent : AppPalette.ink,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [BoxShadow(color: alt ? AppPalette.ink : AppPalette.accent, offset: const Offset(3, 3), blurRadius: 0)],
        ),
        child: Text(label, style: GoogleFonts.kalam(fontSize: 15, fontWeight: FontWeight.w700, color: AppPalette.paper)),
      ),
    );
  }
}

class _Checkbox extends StatelessWidget {
  final bool value;
  final String label;
  final ValueChanged<bool?> onChanged;
  const _Checkbox({required this.value, required this.label, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: AppPalette.ink, width: 1.5),
              color: value ? AppPalette.ink : Colors.transparent,
            ),
            child: value ? const Icon(Icons.check, size: 11, color: AppPalette.paper) : null,
          ),
          const SizedBox(width: 6),
          Text(label, style: GoogleFonts.kalam(fontSize: 12, color: AppPalette.inkSoft)),
        ],
      ),
    );
  }
}

class _EmailPane extends StatelessWidget {
  final TextEditingController emailCtrl;
  final TextEditingController passCtrl;
  final bool passVisible;
  final VoidCallback onPassToggle;
  final bool rememberMe;
  final ValueChanged<bool?> onRememberMe;
  final VoidCallback onSignIn;

  const _EmailPane({
    super.key,
    required this.emailCtrl,
    required this.passCtrl,
    required this.passVisible,
    required this.onPassToggle,
    required this.rememberMe,
    required this.onRememberMe,
    required this.onSignIn,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AuthField(label: 'email', placeholder: 'you@store.in', controller: emailCtrl, keyboardType: TextInputType.emailAddress),
        const SizedBox(height: 10),
        _AuthField(
          label: 'password',
          placeholder: '••••••••',
          controller: passCtrl,
          obscure: !passVisible,
          suffix: GestureDetector(
            onTap: onPassToggle,
            child: Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Icon(passVisible ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 18, color: AppPalette.muted),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _Checkbox(value: rememberMe, label: 'remember me', onChanged: onRememberMe),
            const Spacer(),
            GestureDetector(
              onTap: () {},
              child: Text('forgot?', style: GoogleFonts.kalam(fontSize: 12, color: AppPalette.pen, decoration: TextDecoration.underline, decorationColor: AppPalette.pen)),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _AuthButton(label: 'Sign in →', onTap: onSignIn),
      ],
    );
  }
}

class _PhonePane extends StatelessWidget {
  final TextEditingController phoneCtrl;
  final bool whatsappOk;
  final ValueChanged<bool?> onWhatsapp;
  final VoidCallback onSendOtp;

  const _PhonePane({
    super.key,
    required this.phoneCtrl,
    required this.whatsappOk,
    required this.onWhatsapp,
    required this.onSendOtp,
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
        const SizedBox(height: 14),
        _Checkbox(value: whatsappOk, label: 'WhatsApp OK for OTP', onChanged: onWhatsapp),
        const SizedBox(height: 18),
        _AuthButton(label: 'Send OTP →', onTap: onSendOtp, alt: true),
      ],
    );
  }
}

class _SocialButton extends StatelessWidget {
  final String label;
  const _SocialButton({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppPalette.ink, width: 1.5),
        color: Colors.white.withValues(alpha: 0.35),
      ),
      alignment: Alignment.center,
      child: Text(label, style: GoogleFonts.kalam(fontSize: 13, fontWeight: FontWeight.w700, color: AppPalette.ink)),
    );
  }
}
