# Handoff: AI Accountant — Login & Authentication Flow

## Overview
Mobile login flow for an AI-powered accounting app. User chooses between **Email/Password** or **Phone/OTP** via a segmented slider. Email path goes straight to the app; Phone path verifies a 6-digit OTP first. Both paths land on the Queue (home) screen.

## About the Design Files
The HTML in this bundle is a **design reference prototype** — a low-fidelity wireframe showing structure, flow, and interactions. It is not production code to ship. Recreate these screens in your target codebase (React Native, Flutter, Swift, Kotlin) using your existing patterns and component libraries. If no codebase exists yet, pick the most appropriate mobile framework.

## Fidelity
**Low-fidelity (lofi) wireframes.** Use these for:
- Layout structure & information hierarchy
- Component placement and sizing
- User flows and state transitions
- Interaction behavior

Apply your own design system for final colors, typography, spacing, shadows.

---

## Flow Map

```
Splash (1.2s)
  └── Login entry  ── slider ──┬──[Email]──> Email + Password ──> "You're in!" ──> Queue
                               └──[Phone]──> Phone number ──> OTP (6 digits) ──> "You're in!" ──> Queue
```

- **Email path**: 2 inputs → primary CTA → success → Queue
- **Phone path**: 1 input → primary CTA → OTP screen → verify → success → Queue
- **Back arrow** appears on OTP screen only; tapping returns to login entry

---

## Screens

### 1. Splash
**Purpose:** Brand moment before login. ~1.2s, then auto-routes to Login entry.

**Layout:**
- Vertical centered: brand mark + name + tagline
- Brand mark: 80×80px rounded square with letter "A", tilted slightly, accent-color shadow
- Brand name: "Accountant·AI" (the · is in accent color)
- Tagline: "your books, on autopilot"
- 3 pagination dots at bottom (first active)

### 2. Login Entry
**Purpose:** Decide auth method and enter credentials.

**Layout (top → bottom):**
1. **Brand block** — small mark + "Sign in" or "Welcome back"
2. **Segmented slider** — 2 equal-width options: "Email" | "Phone"
   - Sliding pill background (.3s cubic-bezier transition)
   - Active option text: light; inactive: dark
3. **Form pane** — content changes based on slider
4. **Divider** — "or continue with"
5. **Social row** — Google + Apple buttons (equal width, 50/50)
6. **Footer link** — "new here? create account"

**Email pane:**
- Email input (label "email", placeholder "you@store.in")
- Password input (label "password", masked, eye icon to reveal)
- Row: "remember me" checkbox (left) + "forgot?" link (right)
- Primary CTA: "Sign in →"

**Phone pane:**
- Phone input with "+91" country code prefix (label "phone number", placeholder "98xxx xxxxx")
- Hint text below: "we'll text a 6-digit code"
- Checkbox: "WhatsApp OK for OTP" (checked by default — important for India)
- Primary CTA: "Send OTP →" (accent-color variant)

**Behavior:**
- Slider toggles between panes; only one visible at a time
- Email CTA → success screen
- Phone CTA → OTP screen

### 3. OTP Verification
**Purpose:** Verify 6-digit code from SMS.

**Layout:**
- Back arrow top-left
- 3 progress dots (2 filled, 1 empty)
- Heading: "enter the code"
- Subhead: "sent to +91 98xxx xxxxx"
- 6 OTP input boxes (36×44px each, 6px gap, centered)
  - Filled boxes show large monospace digit
  - Active box has accent-color border + blinking caret
- Resend line: "resend in 00:24" (30s countdown, then becomes tappable "Resend code")
- Primary CTA: "Verify →"
- Numeric keypad at bottom (3-column grid):
  - Rows 1–3: digits 1-9
  - Row 4: "paste" | 0 | "⌫" (backspace)
  - "paste" and "⌫" are dashed-border function keys

**Behavior:**
- Auto-advance focus to next box on digit entry
- SMS auto-read fills all 6 boxes if OS supports it
- Backspace clears current, then moves left
- "Verify" → success screen
- Back arrow → returns to Login entry, preserves entered phone

### 4. Success ("You're in!")
**Purpose:** Brief confirmation, ~1.5s, then auto-route to Queue.

**Layout:**
- Large green check circle (80×80px, 3px green border, slight tilt)
- Heading: "you're in!"
- Subhead: "opening your queue · your AI accountant is ready to go."
- Progress bar (80% width, 4px tall, fills left-to-right over 1.4s)
- Subtle text: "redirecting…"

**Behavior:**
- Progress bar animates fill
- On complete, navigate to Queue (replace stack, no back)

---

## Components

### Segmented Slider
- Container: rounded pill (border-radius 22px), 1.5px border, 3px inner padding, grid 1fr 1fr
- Pseudo-element pill (background fill): absolutely positioned, transforms via `translateX(100%)` when toggled to second option
- Transition: `transform .3s cubic-bezier(.2,.8,.2,1)`
- Active text color flips when behind the pill

### Text Input
- Border-radius 7px, 1.5px solid border
- Padding 8px 10px
- Monospace font for values, sans for labels
- Optional left adornment (country code "+91" with right border)
- Optional right adornment (eye icon for password reveal)
- Label sits above (small italicized handwritten style)
- Hint text below in muted color

### OTP Box
- 36×44px, border-radius 7px
- Monospace 18px bold for digit
- Active state: accent border + blinking 2px underline caret (1s steps blink)

### Primary Button
- Full-width, padding 11px, border-radius 10px
- Background dark, text light
- 3px offset shadow in accent color (3px 3px 0)
- On press: translate(1px,1px) + shadow shrinks to 2px 2px 0
- Variant `.alt`: accent background, ink shadow

### Social Button
- Equal flex width, border-radius 8px, 1.5px border
- Label includes logo glyph: "G · Google", "⌘ · Apple"

### Numeric Keypad
- 3-column grid, 4px gap
- Digit keys: solid border, light background
- Function keys (paste, ⌫): dashed border, transparent background, smaller font

### Progress Dots (Stepper)
- 22px wide × 4px tall rounded bars
- 6px gap
- Active: ink; inactive: 18% opacity ink

---

## Interactions & Animations

| Trigger | Result | Timing |
|---|---|---|
| Tap slider option | Pill slides; panes swap | .3s ease-out |
| Tap "Sign in →" | Navigate to success | instant |
| Tap "Send OTP →" | Navigate to OTP screen | instant; show spinner if real API |
| Type digit in OTP | Focus next box | instant |
| Tap "Verify →" | Navigate to success | show spinner during API call |
| Tap back arrow on OTP | Return to login entry | slide-right transition |
| Land on success | Progress bar fills | 1.4s linear |
| Progress complete | Replace stack with Queue | instant |

**Resend timer:** 30s countdown; while active, link is muted/disabled. After 0:00, becomes active link "Resend code"; tap re-triggers OTP API and restarts countdown.

---

## State

```ts
type LoginState = {
  mode: 'email' | 'phone';
  email: string;
  password: string;
  phone: string;          // without country code
  countryCode: string;    // default '+91'
  whatsappOk: boolean;    // default true
  rememberMe: boolean;    // default true
  loading: boolean;
  error: string | null;
};

type OtpState = {
  phone: string;
  digits: string[];       // length 6
  resendSecondsLeft: number;
  loading: boolean;
  error: string | null;
};
```

---

## Validation

- **Email**: standard regex; show inline error below input
- **Password**: min 8 chars; no real-time feedback, validate on submit
- **Phone**: 10 digits after country code; format display as `98765 43210`
- **OTP**: 6 digits, numeric only; auto-submit on 6th digit (optional) or wait for Verify tap

---

## Edge Cases

- **Wrong password** → inline error under password field, shake animation
- **OTP failure** → red border on all boxes, error message, clear digits
- **OTP expired** → "Code expired" message, force Resend
- **Network error** → toast at top, retain form values
- **Already logged in** → skip login entirely on app launch
- **Email path for new users** — Sign Up screen (not in this wireframe, but should mirror email login + add name + confirm password)

---

## Design Tokens

| Token | Value |
|---|---|
| Background | `#f6f1e6` (paper) |
| Text primary | `#16181d` |
| Text secondary | `#3a3f49` |
| Text muted | `#8a8576` |
| Link color | `#1f3a8a` |
| Accent (CTAs, warnings) | `#d94f3a` |
| Accent 2 (highlight) | `#f2c94c` |
| Success | `#1d7a3a` |
| Border | `#16181d` 1.5px |

**Typography** (replace with your stack):
- Headings: handwritten display (Caveat 700)
- Body: friendly sans (Kalam 400/700)
- Captions/hints: handwritten note (Architects Daughter)
- Numerics & input values: monospace (JetBrains Mono)

**Spacing**:
- Screen padding: 18px horizontal
- Form field gap: 10px
- Section gap: 14px

**Radii**: input 7px · button 10px · pill 22px · OTP box 7px

---

## API Contract (suggested)

```
POST /auth/login/email
  body: { email, password }
  200: { token, user } → Queue
  401: { error: 'invalid_credentials' }

POST /auth/otp/request
  body: { phone, countryCode, channel: 'sms' | 'whatsapp' }
  200: { otpId, resendAfterSec: 30 }

POST /auth/otp/verify
  body: { otpId, code }
  200: { token, user } → Queue
  400: { error: 'invalid_code' | 'expired' }
```

---

## Implementation Steps

1. **Set up navigation stack** for the auth flow: `Splash → Login → OTP → Success`
2. **Build reusable components**: SegmentedSlider, OtpInput (6 boxes), PrimaryButton, FormField
3. **Implement Login screen** with the slider + two form panes
4. **Implement OTP screen** with auto-advance focus, paste support, resend timer
5. **Wire up auth API** with proper loading and error states
6. **Persist auth token** (Keychain / Keystore / Secure Storage — not AsyncStorage)
7. **On app launch**, check token validity; skip to Queue if logged in
8. **Implement Success screen** with animated progress, auto-route on complete
9. **Handle deep-link auto-OTP** if your platform supports SMS retriever API
10. **Add analytics** for funnel drop-off (login_started, otp_requested, otp_verified, login_success)

---

## Files

- `AI Accountant Wireframes.html` — open in browser, click the **"Login flow"** tab; the first phone is interactive (try the slider + run through the full flow).

---

**Questions?** Open the HTML, click into Login flow, and step through the interactive demo phone — every interaction described above is wired up.
