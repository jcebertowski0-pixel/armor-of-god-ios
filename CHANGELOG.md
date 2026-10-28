# Armor of God (iOS) - Release Notes

Build numbers come from the git commit count (`git rev-list --count HEAD`), so every
shipped build needs a new commit before Codemagic runs.

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
