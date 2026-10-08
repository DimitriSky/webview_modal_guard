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

## Round 2 — regression and routing boundaries

No additional important production defect was found. No further runtime code
change was needed. Secondary improvements are recorded in
[future-improvements.md](future-improvements.md).

Expanded qualification on the actual runner proved, for both Settings and URL:

- Nested dialogs hold two independent leases.
- Real background plugin registration leaves both active.
- Hot reload leaves both dialogs and leases active.
- Hot restart clears both; fresh opening/closing acquires/releases normally.
- After both restarts, the routing smoke scenario passes for protected Settings,
  URL and parents after nested child removal: native input reaches Flutter,
  sampled DOM input stays zero, and page load/text/scroll state is preserved.
  This script explicitly reports `trackingAreaQualified: false`.
  In this run, baseline and every post-close sample each received six
  `mousemove` and six `pointermove` events. Each protected sample routed six
  events to Flutter with empty page input counts.

Added regression tests for waiting for native acquisition acknowledgment before
route push, child exit animation while the parent remains protected, independent
left/right button capture outside view bounds, scroll forwarding without drag
capture outside bounds, and native close/minimize/zoom button exemptions when
Flutter extends into the title bar. Scroll/button tests wrap real CG-created
events with a fixture dispatch window and position; they do not post OS input.

Final verification: **10 package Dart/widget tests, 11 standalone AppKit tests,
1 example HTTP test**, all passing; package/example `flutter analyze` reports
no issues; actual macOS Debug runner builds and lifecycle qualification passes.
Results: [engine lifecycle](../example/evidence/engine-lifecycle.json) and
[post-restart routing smoke](../example/evidence/review-routing-smoke.json).

Stopped after two rounds because the reviewed scenarios are stable and no
confirmed important defect remains. Scope stayed within the package and its
owned example. No consumer pins or application code were changed; these commits
must be published before a consuming app can pin the audited revision.
