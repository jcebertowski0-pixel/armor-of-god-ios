# Armor of God (iOS) - Release Notes

Build numbers come from the git commit count (`git rev-list --count HEAD`), so every
shipped build needs a new commit before Codemagic runs.

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
