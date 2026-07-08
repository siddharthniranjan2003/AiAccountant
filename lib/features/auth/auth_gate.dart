import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../data/session_store.dart';
import '../shell/app_shell.dart';
import 'login_screen.dart';
import 'splash_screen.dart';

// ASSUMPTION (important): every user's phone number is registered as a Firebase
// *test* number with this fixed OTP. That is what makes the silent re-login
// below possible — we can re-mint the session non-interactively because the code
// is always the same.
//
// Consequences if that stops being true:
//   * A number NOT registered as a test number gets a REAL SMS OTP. First login
//     still works (user types the real code), but silent re-login will fail
//     (123456 is wrong for them) and they'll be logged out on every restart —
//     i.e. the original persistence bug returns for that user.
//   * To onboard a new user AND keep login persistence, register their number as
//     a test number (Firebase console → Authentication → Sign-in method → Phone →
//     "Phone numbers for testing"), code 123456.
//   * Firebase caps test numbers at ~10 per project, so this login model does not
//     scale past a handful of users. Real per-user OTP would need a different
//     persistence approach (this fix would no longer apply).
const String kFixedOtp = '123456';

/// Signs in silently using a stored phone number + the fixed OTP. Returns true
/// on success. Used to restore the session on cold start when Firebase itself
/// fails to restore it (observed on some release-signed Android builds).
Future<bool> attemptSilentLogin(String phone) {
  final completer = Completer<bool>();

  Future<void> signIn(PhoneAuthCredential credential) async {
    try {
      await FirebaseAuth.instance.signInWithCredential(credential);
      if (!completer.isCompleted) completer.complete(true);
    } catch (_) {
      if (!completer.isCompleted) completer.complete(false);
    }
  }

  FirebaseAuth.instance.verifyPhoneNumber(
    phoneNumber: '+91$phone',
    timeout: const Duration(seconds: 25),
    verificationCompleted: signIn,
    verificationFailed: (_) {
      if (!completer.isCompleted) completer.complete(false);
    },
    codeSent: (verificationId, _) => signIn(
      PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: kFixedOtp,
      ),
    ),
    codeAutoRetrievalTimeout: (_) {},
  );

  return completer.future;
}

/// Auth gate for the app root. Renders the shell when signed in, the login
/// screen when not — but first tries a one-shot silent re-login from a saved
/// number so a dropped Firebase session is transparently restored.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  // One-shot guards for the silent re-login attempt (per gate instance, i.e.
  // per cold start).
  bool _silentTried = false;
  bool _silentRunning = false;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SplashScreen();
        }
        if (snapshot.hasData) {
          return const AccountantShell();
        }
        // No user. Attempt a single silent re-login from a saved number before
        // falling back to the login screen.
        if (_silentRunning || !_silentTried) {
          if (!_silentRunning) {
            _silentRunning = true;
            _runSilent();
          }
          return const SplashScreen();
        }
        return const LoginScreen();
      },
    );
  }

  Future<void> _runSilent() async {
    final phone = await SessionStore.savedPhone();
    if (phone != null && phone.isNotEmpty) {
      // On success, authStateChanges emits the user and rebuilds to the shell.
      await attemptSilentLogin(phone);
    }
    if (mounted) {
      setState(() {
        _silentTried = true;
        _silentRunning = false;
      });
    }
  }
}
