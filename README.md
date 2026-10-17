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

## Build 4 — Clock-style alarm with slide-right acknowledgment (2026-10-17)

The alarm now behaves like the iPhone Clock alarm:

- **Full-screen alarm takeover.** When the alarm fires (notification tapped, or
  app open, or app opened later) a black full-screen alarm appears with the time,
  the event, a LOOPING Radar-style ringtone that plays EVEN ON THE SILENT SWITCH
  (AVAudioSession .playback), and vibration every 1.2 seconds.
- **Slide right to acknowledge.** The only way out is dragging the orange knob
  all the way right, exactly like stopping a Clock alarm. Release early and it
  snaps back. No buttons, no tapping elsewhere.
- **Missed alarms still demand the swipe.** Every scheduled fire is remembered.
  If an alarm rings and is never acknowledged, the app shows the full-screen
  swipe alarm the next time it is opened — however late — until it is swiped.
  Missed alarms queue: if several stack up, they show one after another.
- **Repeat chain.** If the first alert is slept through, the phone rings again
  4 minutes and 8 minutes later with the alarm sound, until acknowledged.
- **Web app updates ASAP.** A swipe-acknowledgment is reported to the web app
  immediately (with auto-relogin if the token expired) and the web dashboard
  reloads right away. Time-Sensitive notification support enabled so alarms
  break through Focus modes.

## Build 5 — Phone Alarms, no ceremony: set, test, pick (2026-10-17)

The Phone Alarms screen is now what an alarm screen should be:

- **Set an alarm directly on the phone.** Pick a time, name it, repeat-daily
  toggle, Add. No account needed. Daily alarms use a repeating iOS trigger, so
  they re-arm themselves even if the app is never opened. One-time alarms fire
  once and then clear themselves after acknowledgment.
- **Test alarm NOW.** One tap shows the real full-screen alarm immediately —
  ringtone, vibration, slide-right. A small link also tests the locked-phone
  notification chain (rings in 15 s).
- **Ringtones:** Radar (default), Siren, Buzzer, Bell — tap one to hear a
  4-second preview; all alarms re-arm with the new sound.
- **Alarm screens:** Clock face (default — giant live "05:47 AM" digital clock
  like the Phone Alarms tile), Dark (big event time + title), Red (war-room).
- **Sign-in demoted to an optional "Calendar sync" section** at the bottom — it
  only adds web-app calendar event alarms (day before + one hour before each
  event). Manual alarms never require it.
- Bug fix: a resync no longer erases unacknowledged missed alarms — the swipe
  demand survives every reschedule.

## Apple's honest limits (different from Android)

- **Notification sounds respect the mute switch** — but the full-screen alarm's
  ringtone does NOT (it plays at full volume even on silent). So: if the phone
  is locked and the app is closed, the notification rings (mute switch rules
  apply, as with any app except Apple's own Clock); the moment the app is
  opened or the notification is tapped, the looping alarm plays at full volume
  regardless of the mute switch.
- **Apple does not let an app wake itself and take over the screen from a cold
  state** like the Clock app can. The repeat chain (re-ring at +4 and +8 min)
  plus the missed-alarm swipe demand on every app open is as close as iOS
  allows. (Apple offers a "Critical Alerts" entitlement that bypasses the mute
  switch, but it requires an approval request to Apple — the owner can decide
  if they want to pursue that:
  https://developer.apple.com/contact/request/notifications-critical-alert-entitlement/)
- The alarm sound (AlarmSound.wav in the project) can be replaced with any
  30-second .wav/.caf file named AlarmSound.

## Updating later

The web app part updates automatically (it loads the live site). Native changes
(alarm behavior) require rebuilding in Xcode.
