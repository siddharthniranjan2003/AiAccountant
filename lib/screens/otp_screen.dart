import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/palette.dart';
import 'success_screen.dart';

class OtpScreen extends StatefulWidget {
  final String phone;
  final String verificationId;
  const OtpScreen({super.key, required this.phone, required this.verificationId});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final List<String> _digits = List.filled(6, '');
  int _focusIndex = 0;
  int _resendSeconds = 30;
  Timer? _resendTimer;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _resendTimer?.cancel();
    setState(() => _resendSeconds = 30);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        if (_resendSeconds > 0) {
          _resendSeconds--;
        } else {
          t.cancel();
        }
      });
    });
  }

  void _inputDigit(String d) {
    if (_focusIndex >= 6) return;
    setState(() {
      _digits[_focusIndex] = d;
      if (_focusIndex < 5) _focusIndex++;
    });
  }

  void _backspace() {
    setState(() {
      if (_digits[_focusIndex].isNotEmpty) {
        _digits[_focusIndex] = '';
      } else if (_focusIndex > 0) {
        _focusIndex--;
        _digits[_focusIndex] = '';
      }
    });
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData('text/plain');
    final raw = data?.text ?? '';
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 6 && mounted) {
      setState(() {
        for (int i = 0; i < 6; i++) { _digits[i] = digits[i]; }
        _focusIndex = 5;
      });
    }
  }

  void _verify() {
    if (_loading) return;
    _doVerify();
  }

  Future<void> _doVerify() async {
    final otp = _digits.join();
    if (otp.length < 6) return;
    setState(() { _loading = true; _error = null; });
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: widget.verificationId,
        smsCode: otp,
      );
      await FirebaseAuth.instance.signInWithCredential(credential);
      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, _, _) => const SuccessScreen(),
            transitionsBuilder: (_, anim, _, child) =>
                FadeTransition(opacity: anim, child: child),
            transitionDuration: const Duration(milliseconds: 350),
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.code == 'invalid-verification-code'
              ? 'Wrong code. Check and try again'
              : 'Verification failed. Try again';
        });
      }
    }
  }

  String get _maskedPhone {
    final p = widget.phone.replaceAll(RegExp(r'\D'), '');
    if (p.length < 2) return widget.phone;
    return '${p.substring(0, 2)}xxx xxxxx';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.paper,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 16),
                    // Back arrow
                    Align(
                      alignment: Alignment.centerLeft,
                      child: GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: AppPalette.ink,
                              width: 1.5,
                            ),
                          ),
                          child: const Icon(
                            Icons.arrow_back_rounded,
                            size: 18,
                            color: AppPalette.ink,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Progress dots
                    Row(
                      children: [
                        _ProgDot(filled: true),
                        const SizedBox(width: 6),
                        _ProgDot(filled: true),
                        const SizedBox(width: 6),
                        _ProgDot(filled: false),
                      ],
                    ),
                    const SizedBox(height: 28),
                    Text(
                      'enter the code',
                      style: GoogleFonts.caveat(
                        fontSize: 34,
                        fontWeight: FontWeight.w700,
                        color: AppPalette.ink,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'sent to +91 $_maskedPhone',
                      style: GoogleFonts.kalam(
                        fontSize: 13,
                        color: AppPalette.inkSoft,
                      ),
                    ),
                    const SizedBox(height: 32),
                    // OTP boxes
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(6, (i) {
                        return Padding(
                          padding: EdgeInsets.only(right: i < 5 ? 6 : 0),
                          child: _OtpBox(
                            digit: _digits[i],
                            isActive: i == _focusIndex,
                            onTap: () => setState(() => _focusIndex = i),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 20),
                    Center(
                      child: _resendSeconds > 0
                          ? Text(
                              'resend in 0:${_resendSeconds.toString().padLeft(2, '0')}',
                              style: GoogleFonts.kalam(
                                fontSize: 13,
                                color: AppPalette.muted,
                              ),
                            )
                          : GestureDetector(
                              onTap: _startTimer,
                              child: Text(
                                'Resend code',
                                style: GoogleFonts.kalam(
                                  fontSize: 13,
                                  color: AppPalette.pen,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                    ),
                    const SizedBox(height: 28),
                    if (_error != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: AppPalette.accent.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(
                            color: AppPalette.accent.withOpacity(0.3),
                          ),
                        ),
                        child: Text(
                          _error!,
                          style: GoogleFonts.kalam(
                            fontSize: 12,
                            color: AppPalette.accent,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (_loading)
                      const LinearProgressIndicator()
                    else
                      _AuthButton(label: 'Verify →', onTap: _verify),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
            _NumKeypad(
              onDigit: _inputDigit,
              onBackspace: _backspace,
              onPaste: _paste,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Shared auth button ────────────────────────────────────────────────────

class _AuthButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _AuthButton({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: AppPalette.ink,
          borderRadius: BorderRadius.circular(10),
          boxShadow: const [
            BoxShadow(
              color: AppPalette.accent,
              offset: Offset(3, 3),
              blurRadius: 0,
            ),
          ],
        ),
        child: Text(
          label,
          style: GoogleFonts.kalam(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppPalette.paper,
          ),
        ),
      ),
    );
  }
}

// ─── Progress dot ─────────────────────────────────────────────────────────

class _ProgDot extends StatelessWidget {
  final bool filled;
  const _ProgDot({required this.filled});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 4,
      decoration: BoxDecoration(
        color: filled
            ? AppPalette.ink
            : AppPalette.ink.withOpacity(0.18),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

// ─── OTP box ───────────────────────────────────────────────────────────────

class _OtpBox extends StatelessWidget {
  final String digit;
  final bool isActive;
  final VoidCallback onTap;

  const _OtpBox({
    required this.digit,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: isActive ? AppPalette.accent : AppPalette.ink,
            width: isActive ? 2.0 : 1.5,
          ),
          color: Colors.white.withOpacity(0.45),
        ),
        child: digit.isEmpty
            ? (isActive ? const _BlinkingCaret() : const SizedBox.shrink())
            : Text(
                digit,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: AppPalette.ink,
                ),
              ),
      ),
    );
  }
}

class _BlinkingCaret extends StatefulWidget {
  const _BlinkingCaret();

  @override
  State<_BlinkingCaret> createState() => _BlinkingCaretState();
}

class _BlinkingCaretState extends State<_BlinkingCaret> {
  bool _visible = true;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) { setState(() => _visible = !_visible); }
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _visible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 80),
      child: Container(width: 2, height: 22, color: AppPalette.accent),
    );
  }
}

// ─── Numeric keypad ────────────────────────────────────────────────────────

class _NumKeypad extends StatelessWidget {
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onPaste;

  const _NumKeypad({
    required this.onDigit,
    required this.onBackspace,
    required this.onPaste,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppPalette.paper,
        border: Border(
          top: BorderSide(color: AppPalette.line, width: 1.2),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
      child: Column(
        children: [
          _keyRow(['1', '2', '3']),
          const SizedBox(height: 6),
          _keyRow(['4', '5', '6']),
          const SizedBox(height: 6),
          _keyRow(['7', '8', '9']),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: _FnKey(label: 'paste', onTap: onPaste)),
              const SizedBox(width: 6),
              Expanded(
                child: _DigitKey(digit: '0', onTap: onDigit),
              ),
              const SizedBox(width: 6),
              Expanded(child: _FnKey(label: '⌫', onTap: onBackspace)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _keyRow(List<String> digits) {
    return Row(
      children: digits.asMap().entries.map((e) {
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(left: e.key > 0 ? 6 : 0),
            child: _DigitKey(digit: e.value, onTap: onDigit),
          ),
        );
      }).toList(),
    );
  }
}

class _DigitKey extends StatelessWidget {
  final String digit;
  final ValueChanged<String> onTap;

  const _DigitKey({required this.digit, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onTap(digit),
      child: Container(
        height: 46,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppPalette.ink, width: 1.5),
          color: Colors.white.withOpacity(0.45),
        ),
        alignment: Alignment.center,
        child: Text(
          digit,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: AppPalette.ink,
          ),
        ),
      ),
    );
  }
}

class _FnKey extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _FnKey({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: CustomPaint(
        painter: _DashedBorderPainter(),
        child: SizedBox(
          height: 46,
          child: Center(
            child: Text(
              label,
              style: GoogleFonts.kalam(
                fontSize: label == '⌫' ? 18 : 12,
                color: AppPalette.inkSoft,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppPalette.inkSoft
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;

    const dashW = 4.0;
    const dashGap = 3.0;
    const r = 8.0;

    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(0.7, 0.7, size.width - 1.4, size.height - 1.4),
        const Radius.circular(r),
      ));

    for (final metric in path.computeMetrics()) {
      double d = 0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + dashW), paint);
        d += dashW + dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) => false;
}
