# Armor of God (iOS) - Release Notes

Build numbers come from the git commit count (`git rev-list --count HEAD`), so every
shipped build needs a new commit before Codemagic runs.

## v2.0 (build 85) - 2026-11-12
- Voice fix: the microphone on the calendar's "speak your event" flow could spin
  forever. The page's promise only ever settled on a final transcript or an error,
  so a stalled audio session left it pending with no message.
  - Native: the bridge now remembers the web view that sent the message (emit used
    to fail silently if the weak reference was gone), validates the input format
    before installing the tap, logs each permission step to the alarm diagnostics
    log, and runs a 15 second watchdog that always answers the page.
  - JS: listen() settles exactly once and rejects after 20 seconds instead of
    hanging, so the button can never be left spinning.
- No change to Shield and Guide here: those are web-side and appear once the app
  is published from the Base44 editor.

## v2.0 (build 84) - 2026-11-11
- TestFlight build of the 2.0 shell, cut after 2.0 build 67 went into App Store
  review so testers keep receiving builds while the review is pending.
- No native code changes since build 67: this commit advances the build number
  because TestFlight rejects a reused one.
- The app loads the live web app, so feature changes made in the Base44 editor
  reach installed shells without a rebuild once the web app is published.

## v1.9 (build 63) - 2026-11-04
- Final TestFlight build of the voice release. No behaviour change from build 62:
  this commit exists to advance the build number (TestFlight rejects a reused one)
  and to record the shipping state below.
- Confirmed live on build 62: `processingState` VALID and `internalBuildState`
  IN_BETA_TESTING, so internal testers receive it automatically with no review.
- Voice: tap the mic on Common Scriptures (Oracle) or Spartan Heart, speak instead of
  typing, and hear the answer through earbuds via the on-device speech engine.
- Siri shortcuts: routine, workout, daily reflection, upcoming alarms, next birthday,
  log an expense, log income. Apple requires the app name inside third-party phrases,
  so the wording is "Hey Siri, ask Armor of God what my workout is".
- Desktop installers are invite only (owner account) until they have been tested.

## v1.9 (build 62) - 2026-11-04
- First shipped voice build. Siri shortcuts wired through App Intents; the free-form
  "ask" shortcut collects the question with a spoken prompt because Siri phrases only
  accept enum/entity parameters.

## v1.7 (build 58) - 2026-11-03
- Fix: page content sliding under the web app's fixed top header. Every screen
  except Home lost its first ~60px (the section title plus the top of the first
  card) because the header is `position: fixed` and the web build being served
  does not pad the scroll area for it. The shell now injects a small guard that
  puts that header back in the layout flow whenever the page would otherwise be
  clipped. It never touches Home, and it removes itself automatically once the
  published web build offsets the content on its own (padding >= 40px), so it
  cannot double up with a future web-side fix.
- Marketing version 1.6 -> 1.7.

## v1.4 (build 46) - 2026-10-28
- Re-release of v1.4 to TestFlight (internal testing) from current `main`.
- Single-swipe alarm acknowledgement: pan gesture is attached to the whole slider
  track, the knob jumps to the finger, and the ack constraint is stored strongly, so
  the alarm can always be dismissed.
- Post-ack crash hardening: acknowledgement work completes before the dismissal
  animation, timers are invalidated in `viewWillDisappear`, and the next alarm is
  presented after an async hop instead of inside a dismissal completion.
- One acknowledgement per calendar event, plus preserved repeat/snooze chains.

## v1.3 (build 44 area)
- One-ack-per-event logic; reduced accidental double acknowledgements.

## v1.2 (build 36)
- Slider fix verified end-to-end; `beta_groups` removed because Apple permanently
  rejects assigning internal TestFlight groups (internal testers get builds
  automatically).

## v2.0 - 2026-11-06
- Shell builds on the live web release (always-visible duration/lift/rest timer with voice cues and blue rest phase; sets/reps/weight with last-week history and Lifting Progress; guided Chef with quantity validation, prep checklist and custom timers; birthday month/day list with optional birth year; upcoming events/birthdays in Daily Acknowledgment).
- No WebView/native behaviour changes; the wrapper loads https://divine-armor-path.base44.app live.
