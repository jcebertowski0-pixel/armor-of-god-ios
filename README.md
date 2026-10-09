# Armor of God — iPhone App (Calendar + Aggressive Alarms)

This is the complete, ready-to-build Xcode project for the Armor of God iPhone app:
the full web app (calendar, planner, everything) in a native shell, plus the native
alarm engine. Plant an event in the calendar and the phone gets two reminders:
**the day before** and **the day of, one hour before** — each with a loud alarm
sound, vibration, and **Acknowledge / Snooze** buttons that persist on the lock
screen until addressed. Acknowledgments sync back to the web app's calendar.

Requirements: iPhone on iOS 16 or newer.

## One-time build (needs a Mac)

1. On a Mac, install **Xcode** (free from the Mac App Store).
2. Unzip this folder, then double-click **ArmorOfGod.xcodeproj**.
3. In Xcode, click the "ArmorOfGod" target → **Signing & Capabilities**:
   - Check "Automatically manage signing"
   - Team: select **Free Bird Applications** (your paid Apple developer account)
   - (Recommended) Click **+ Capability** → add **Time Sensitive Notifications**
4. Plug the iPhone in with a cable. First time only: on the iPhone go to
   Settings → Privacy & Security → **Developer Mode** → ON → restart.
   (Only needed while installing via cable; not needed once on the App Store.)
5. In Xcode, select your iPhone at the top and press **Cmd+R** (Run).

## On the phone, first run

1. Open the app → tap the **bell** button (top right).
2. Tap **"1. Allow notifications"** → Allow.
3. Sign in with the Armor of God account (the same account whose calendar
   events should fire on this phone).
4. Tap **"Test alarm in 15 seconds"**, then lock the phone and wait.

After that, no setup needed: every time the app is opened it re-syncs the
calendar and re-arms all alarms automatically.

## Apple's honest limits (different from Android)

- **No forced screen takeover.** Apple doesn't allow any app to take over the
  screen or block dismissal. What you get: a time-sensitive notification with an
  alarm sound and vibration that stays on the lock screen until acknowledged.
- **The mute switch silences notification sounds.** For can't-miss events, keep
  the mute switch off. (Apple offers a special "Critical Alerts" entitlement that
  bypasses the mute switch, but it requires an approval request to Apple — the
  owner can decide if they want to pursue that:
  https://developer.apple.com/contact/request/notifications-critical-alert-entitlement/)
- The alarm sound (AlarmSound.wav in the project) can be replaced with any
  30-second .wav/.caf file named AlarmSound.

## Updating later

The web app part updates automatically (it loads the live site). Native changes
(alarm behavior) require rebuilding in Xcode.
