# Package review loops · 2026-10-08 · WV-MODAL-GUARD

Scope: this package's Dart lease/dialog lifecycle, native AppKit routing, and
its owned example. Consumer applications and unrelated WebView functionality
are outside this review. Each completed round has a `loop` commit; maximum five
rounds, stopping when no important defect remains in the reviewed scenarios.

## Round 1 — root-isolate restart lifecycle

### Ranked findings

1. **P1, fixed: stale native lease after hot restart.** Reproduced on the actual
   macOS example runner: Settings open reported one dialog/one lease. After
   `R`, the new app reported zero dialogs but one native lease. The old local
   monitor remained active even though its Dart owner no longer existed.
2. **Investigated, not a confirmed defect:** reading `buttonNumber` for tracking
   events. Real AppKit `mouseEntered`/`mouseExited` events did not crash on this
   host; no crash claim is made. Added coverage that these foreign tracking
   notifications are consumed without forwarding hover state to Flutter.

### Change

Flutter's generated Dart plugin registrant sends a native reset once when the
root isolate starts. Native reset disposes the old router and removes its
monitor. Acquisition/status await reset acknowledgment before continuing.
Background registrants return without resetting live UI leases. The hook uses
the public platform dispatcher before bindings exist, leaving app binding
selection to the app. Existing token and dialog APIs remain compatible.

### Verification

- Baseline: 7 AppKit tests passed before changes.
- After changes: 8 package Dart/widget tests and 8 AppKit tests passed.
- `flutter analyze`: no issues.
- Actual macOS runner built and passed `example/tool/qualify_lifecycle.py`:
  Settings and URL each opened with a nested dialog (two leases); a real
  background-isolate registrant preserved both; hot restart restored zero
  dialogs/zero leases; reopen/close returned one lease to zero.
- Count-only result: [engine-lifecycle.json](../example/evidence/engine-lifecycle.json).

These lifecycle and native policy checks do not qualify physical WebKit hover
or every trackpad gesture. Existing physical-input evidence is retained
separately; routing smoke and physical qualification must not be conflated.
