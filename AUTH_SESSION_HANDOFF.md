# Auth / Login-Persistence — Session Handoff

> Purpose: full context for a new chat or a new developer picking up the login-persistence work
> on the AI Accountant Flutter app. Written 2026-07-06. Covers what was investigated, the root
> cause status, the fix that shipped, how to test it, and the important caveats.

---

## 1. TL;DR

- **Symptom:** On **release (production) Android builds**, users were logged out every time the app
  was killed and reopened — dumped back to the login screen. Debug builds and the emulator were fine.
- **Cause:** Firebase silently fails to restore its own auth session on cold start, but **only** on
  release-signed, sideloaded builds on a real device. The standard causes were all ruled out
  (SHA registration, API-key restrictions, App Check, minification) and the exact internal mechanism
  was **never definitively identified**.
- **Fix (shipped):** Instead of relying on Firebase to *restore* the session, the app now **silently
  re-logs the user in on launch**. Because the OTP is a fixed test code, re-auth is deterministic.
- **Status:** Verified end-to-end on the real release build. Code is **uncommitted** on branch
  `feature/scan-loading-timer-loop`.

---

## 2. App background (what this app is)

- Flutter app, single **client/tenant** accounting tool ("AI Accountant"). Bottom nav:
  Queue / History / Camera / Report / Profile.
- **Auth:** Firebase **Phone Auth (OTP)**, India-only (`+91` hard-prefixed). No password/email.
- **Backend (Cloud Run):** called via `lib/services/api_client.dart`. Every request sends
  `Authorization: Bearer <Firebase ID token>` + a static `x-api-key`. Reports, invoice images,
  and push-to-Tally all use this (token-dependent).
- **Supabase:** used for realtime queue + data reads, with the **anon key only** (not per-user scoped).
- **Flavors:** `staging` (→ Firebase *testing* project), `deployment`, `prod`. Each has its own
  `android/app/src/<flavor>/google-services.json`. Build must pair with
  `--dart-define-from-file=env/<flavor>.json`. (Note: the "staging" flavor uses the testing project;
  Gradle forbids flavor names starting with "test".)
- **Distribution:** direct APK / **Firebase App Distribution** — NOT the Play Store. This matters
  (see root cause) because the failing config is the real shipping config.

### How the OTP login actually works here (important)
The client originally wanted **PIN-style** auth. OTP was already built, so they kept OTP but made it
behave like a PIN: **each user's phone number is registered as a Firebase _test number_ with a fixed
OTP `123456`.** So there is no real SMS for existing users — everyone types their number + `123456`.

---

## 3. How auth is wired (code map)

- `lib/features/auth/login_screen.dart` — enter phone → `FirebaseAuth.verifyPhoneNumber('+91$phone')`.
- `lib/features/auth/otp_screen.dart` — enter 6-digit code → `PhoneAuthProvider.credential` →
  `signInWithCredential`.
- `lib/features/auth/success_screen.dart` — animation, then pops back to the gate route.
- `lib/main.dart` — app root gate. **Was** an inline `StreamBuilder<User?>(authStateChanges())`
  (waiting→Splash, hasData→Shell, else→Login). **Now** uses `AuthGate` (see fix).
- `lib/services/api_client.dart` — `_headers()` calls `currentUser.getIdToken()` for the Bearer token.

---

## 4. The bug

On a real device (Samsung Galaxy S24) running the **release** build, after force-stop + relaunch,
the app returns to the **Login** screen — the Firebase session is not restored. First reported by the
user via screenshots; reproduced directly.

---

## 5. Investigation — what was tested and ruled out

Reproduced cleanly and isolated the variable with an A/B matrix (same source, fresh installs):

| Build mode | Signing key | Device | Session persists after kill? |
|---|---|---|---|
| debug | debug | S24 | ✅ yes |
| release (AOT) | **debug** | S24 | ✅ yes |
| release (AOT) | **release** | S24 | ❌ **NO** (the production build) |
| release (AOT) | release | emulator | ✅ yes |

So it fails **only** on the true production profile: release-key + AOT + non-debuggable, **sideloaded**,
on a **real device**.

On-disk check (via `run-as` on the debug build): the encrypted Firebase auth store
(`shared_prefs/com.google.firebase.auth.api.Store.*.xml`) **is written after login and survives the
force-stop**. So it's a **restore** failure, not a persistence/wipe, and not a Dart/gate bug.

**Ruled out (with evidence):**
- **Firebase SHA fingerprint registration** — release SHA-1 and SHA-256 are already registered in the
  Firebase console (testing project). Not it.
- **Google Cloud API-key restrictions** — the Android API key's Application restrictions = **None**,
  and API restrictions include **Identity Toolkit API** + **Token Service API**. Not it.
- **App Check / Play Integrity** — not used anywhere in the app (no `firebase_app_check`). Not it.
- **R8 / minification** — turned OFF in `build.gradle.kts` (no ProGuard rules). Not it.
- Release logs are silent (no `debugPrint`, not debuggable) and GmsCore logs no auth rejection at any
  visible level. Firebase inits cleanly (`FirebaseApp initialization successful`) then simply comes up
  with **no user**.

**Root cause: NOT definitively identified.** Empirically it tracks the production build profile;
the exact reason Firebase drops a (test-number) session on a sideloaded release build is unknown.
A dead-end was `isDebuggable=true` on release — it flips Flutter into the **debug engine**, so it can't
be used to test the true release build (confounded).

---

## 6. The fix that shipped — silent auto re-login

Since the OTP is a fixed code, re-authentication is deterministic, so we stop depending on Firebase's
(unreliable) restore and **silently re-login on launch**.

### Behavior
1. On successful login, **save the phone number** (shared_preferences).
2. On cold start: the gate checks Firebase's own `authStateChanges()` first. If a user is restored →
   shell (normal path, no re-login needed).
3. If **no** user but a saved number exists → run a **one-shot silent** `verifyPhoneNumber` +
   `signInWithCredential(smsCode: '123456')` in the background, showing the Splash meanwhile.
4. On success, the auth stream emits the user → shell. On failure/no saved number → Login screen.
5. **Sign out clears the saved number** so it doesn't auto-log-back-in (no loop).

### Why it's safe for the rest of the app
Silent re-login is a **real** `signInWithCredential` — same **uid**, valid **ID token**. So every
backend feature (`ApiClient.get/post/getRaw/getBytes`: reports, invoice images/PDF, push-to-Tally)
gets the exact session it would after a manual login. It only touches the auth gate.

### Files changed (branch `feature/scan-loading-timer-loop`, uncommitted)
- **NEW** `lib/data/session_store.dart` — `savePhone` / `savedPhone` / `clear` (shared_preferences).
- **NEW** `lib/features/auth/auth_gate.dart` — `AuthGate` widget + `attemptSilentLogin()` +
  `const kFixedOtp = '123456'` (with a big assumption comment — see §8).
- `lib/main.dart` — `home:` now `const SelectionArea(child: AuthGate())`; removed now-unused imports.
- `lib/features/auth/otp_screen.dart` — `SessionStore.savePhone(widget.phone)` after sign-in.
- `lib/features/auth/login_screen.dart` — `SessionStore.savePhone(phone)` in the auto-verify path.
- `lib/features/profile/profile_screen.dart` — `SessionStore.clear()` before `signOut()`.
- `android/app/build.gradle.kts` — **reverted** to original (a temporary `isDebuggable=true` diagnostic
  was added then removed; net: unchanged).

---

## 7. Verification done (on the real release build, S24)

- Login → force-stop → relaunch **×2** → lands on **Queue** (silent re-login worked). ✅
- **Sign out** → Login screen and **stays** there (no auto-relogin loop). ✅
- After a silent re-login, opened the **`/act_now` report** → full live backend data returned
  ("Sorted By Closing stock amount – ₹1,13,88,652 · 2022 Items"). Proves the Firebase **token still
  works** for backend calls post-restore (covers reports + PDF/image + push, same token path). ✅
- `flutter analyze` on all changed files: **No issues found**.

---

## 8. Caveats / limitations (READ before onboarding users or scaling)

- **The fix assumes every user's number is a Firebase _test number_ with code `123456`.**
  - A number NOT registered as a test number gets a **real SMS OTP**. First login still works, but
    silent re-login will fail (123456 is wrong for them) → they'd be logged out on every restart
    (original bug returns for that user).
  - To onboard a new user AND keep persistence: register their number as a test number
    (Firebase console → Authentication → Sign-in method → Phone → "Phone numbers for testing"), code `123456`.
- **Firebase caps test numbers at ~10 per project** → this login model does not scale past a handful
  of users. Real per-user OTP would need a different persistence approach (this fix wouldn't apply).
- **Offline cold start:** silent re-login needs network. If a user opens the app offline *and* Firebase
  dropped the session, they'll see Login until back online. (Still strictly better than today, since
  these builds lose the session regardless.)
- **Web:** the bug was Android-only. The fix code is shared Dart so it runs on web too, but it's
  effectively a no-op there (web phone-auth needs a reCAPTCHA popup and can't re-login silently) — it
  just falls back to the normal login screen. Web is unaffected.
- When building the shipping flavor (`deployment`/`prod`), the fix applies automatically (shared Dart) —
  just rebuild that flavor.

---

## 9. How to build / test

```bash
# Normal dev/testing (DEBUG build — will NOT reproduce the release-only bug, but fine for everything else)
flutter run --flavor staging --dart-define-from-file=env/testing.json

# To test THIS fix, you must use a RELEASE build on a real device:
flutter build apk --release --flavor staging --dart-define-from-file=env/testing.json
# → install build/app/outputs/flutter-apk/app-staging-release.apk, then: login → kill → reopen

# adb is not on PATH; full path:
#   C:\Users\panka\AppData\Local\Android\Sdk\platform-tools\adb.exe
# Useful repro loop:
#   adb -s <serial> shell am force-stop com.example.aiaccountant
#   adb -s <serial> shell am start -n com.example.aiaccountant/.MainActivity
```

Test login: any registered number + OTP `123456` (e.g. `9560952125` / `123456`).

---

## 10. Environment / reference facts

- **App package:** `com.example.aiaccountant` (a `com.example.dev_aiaccountant` also exists on the test phone).
- **Physical test device:** Samsung Galaxy S24, `SM-S921B`, adb serial `RZCY411B39T`, arm64, Android 16.
  (Has a secure lockscreen — needs manual unlock for UI automation; screen-off drops the adb UI stream.)
- **Emulator:** `emulator-5554`, Android 17, x86_64 (does NOT reproduce the bug — no Play Integrity enforcement).
- **Firebase testing project:** `tallybridge-testing-env-636d4`, project number `639712744833`,
  App ID `1:639712744833:android:9903b17e6e259236c00480`. (Confusingly there's a *different* GCP
  project also named "Tally Bridge Testing Env", number `828647628834` — not the app's project.)
- **Release keystore:** `android/app/upload-keystore.jks`, alias `upload` (password in
  `android/key.properties`, gitignored — do NOT lose the keystore).
  - SHA-1: `E8:4E:8C:49:6C:35:5F:76:B2:71:97:1D:09:F8:C8:B2:85:38:9B:A0`
  - SHA-256: `53:37:61:7A:15:66:82:7C:B1:01:0B:74:5D:92:9C:E5:1E:67:AC:78:6D:D3:E7:F1:17:D1:C0:A3:26:02:26:9F`
- **Tooling used:** the `mobile` MCP server (`@mobilenext/mobile-mcp`) was added to this project's
  `.mcp.json` (copied from the TallyBridge project) to drive the phone/emulator; plus `adb` via Bash.

---

## 11. Open items / next steps

- [ ] Commit the changes (still uncommitted on `feature/scan-loading-timer-loop`).
- [ ] Rebuild + smoke-test the actual shipping flavor (`deployment`/`prod`) on a real device.
- [ ] Decide the long-term auth plan if user count will exceed ~10 (test-number cap) or move to real OTP.
- [ ] Optional cleanup: stale test APKs under `build/app/outputs/` and test builds on the S24.
