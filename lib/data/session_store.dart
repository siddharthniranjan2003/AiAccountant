import 'package:shared_preferences/shared_preferences.dart';

/// Persists the phone number the user last authenticated with, so the app can
/// silently re-authenticate on cold start.
///
/// This works around Firebase failing to restore its own persisted session on
/// some production (release-signed) Android builds. Because each user's number
/// is a Firebase test number with a fixed OTP, re-login is deterministic and we
/// can re-mint the session without any user interaction. See [AuthGate].
class SessionStore {
  static const _kPhoneKey = 'auth_phone';

  static Future<void> savePhone(String phone) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPhoneKey, phone);
  }

  static Future<String?> savedPhone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kPhoneKey);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPhoneKey);
  }
}
