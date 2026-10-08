# WebView Modal Lab · #WV-MODAL-GUARD

Standalone macOS Flutter reproduction app for native WebView mouse events leaking through Flutter Settings/URL dialogs. It lives in the `webview_modal_guard` repository under `example/` and depends on the package source at `path: ..`. This app contains the probe, baseline/protected switch, popup controls, and evidence. SimpleWebBrowser integration is a separate task.

## Run

From the repository root:

```sh
cd example
flutter pub get
flutter run -d macos
```

The left panel displays the loopback diagnostic URL, also printed as `MODAL_LAB_URL=http://127.0.0.1:<port>`. The owned page is served from this app; no remote site or file URL is involved. The server binds only IPv4 loopback, closes with the app, and exposes `/state` and test-only `/action`. Do not add it to a production application.

This lab matches SimpleWebBrowser's `flutter_inappwebview: 6.1.5`, resolved macOS implementation 1.1.2, and Git-pinned `webview_key_guard` commit `7965c50689fb58c2bc4f9859c8f9e9b58eb7e88c`. The old repeated-keys lab uses another WebView plugin, so it supplied the harness pattern rather than the native reproduction stack.

## Before / after

With **Native protection off**, open Settings or URL. Move the real mouse around the popup and over the dimmed webpage. Page counters can grow and CSS hover changes under the modal. In the captured Settings baseline, DOM received 49 trusted `mousemove`, 49 trusted `pointermove`, and 3 of each inside the iframe.

With **Native protection on**, repeat. Flutter popup hover and slider should respond, its field should edit, and scrolling must stay within Flutter. Page input counts must remain zero. Close the popup: WebView events must resume without changing the page's load identity, field value or scroll position. Open a nested dialog: leases go 1 → 2 → 1 → 0 as child and parent close. The switches cannot change modal protection while a dialog is active; keyboard guard can be toggled for compatibility checks.

Counter reset redraws page diagnostics; it does not reload the page or change its text/scroll state. CSS hover already active before opening a popup may remain active; new mouse delivery is the qualification criterion.

## Automated routing checks

```sh
flutter analyze
flutter test
python3 tool/qualify.py http://127.0.0.1:<port>
```

Close all dialogs before starting the script. It posts `NSEvent`s only into this lab's own AppKit queue; it does not inject OS-wide input. It verifies native plugin registration, protected movement reaching Flutter, zero page input, nested lease lifetimes, route removal and preserved page identity. This is a **routing smoke test**, not physical hover qualification: self-posted events do not reliably activate AppKit/WebKit tracking areas even in baseline mode.

## Physical-input qualification

```sh
python3 tool/qualify.py http://127.0.0.1:<port> --physical --seconds 10
```

Immediately return to the lab and continuously move the real mouse across the webpage area and the popup, including the iframe. Do not click the dismissing barrier during the measurement. The script changes between baseline Settings, protected Settings, protected URL, parent after nested close, and WebView after close. It resets counters for each interval, waits for complete route removal, saves evidence, and restores protection on exit.

A valid physical qualification requires all of these: baseline reproduces, protected input is observed by both the native router and Flutter, DOM receives no movement/click/wheel, nested close remains protected, and input resumes after final close. Zero DOM counts without observed input are inconclusive. Repeat manual field, slider, right-click, scroll, Escape and barrier dismissal checks, and verify a separate native window remains interactive.

## Engine lifecycle qualification

With other lab instances closed, run from `example/`:

```sh
python3 tool/qualify_lifecycle.py
```

The script launches and closes its own macOS runner. For Settings and URL it
opens nested dialogs, registers a real background isolate while both leases
are live, verifies hot reload retains both, hot restarts the root isolate,
and checks zero stale leases followed by successful reopen/close. Finally it
runs the routing smoke scenario after the restarts. It uses the owned loopback API and Flutter CLI;
it does not qualify physical hover. Count-only evidence is written to
`evidence/engine-lifecycle.json`.

## Evidence and current status

- `evidence/real-baseline-settings.json`: actual trusted page movement observed while baseline Settings was open; confirms the bug in this native stack. The input source was not controlled for this captured interval.
- `evidence/self-posted-baseline-inconclusive.json`: original unsuccessful attempt to reproduce tracking-area hover using posted NSEvents. Kept as a limitation, not a passing qualification.
- `evidence/guarded-settings-controls.json`: protected slider/text/scroll interactions; zero page counts, page state preserved. CUA app interaction was used for controls; this does not establish continuous physical hover isolation.
- `evidence/guarded-url-scroll.json`: protected URL popup scrolled by 276 pixels, its slider and field responded, underlying page remained at scroll zero with no DOM input.
- `evidence/escape-and-restored-scroll.json`: Escape removed the popup and final lease; WebView then received a trusted wheel event and scrolled normally.
- `evidence/nested-scopes.json`: two scopes while nested, one after child removal, no page input.
- `evidence/baseline-keyboard-shortcut.json`: CUA `super+a` did not select all in either mode in this harness. Typing works. Shortcut equivalence requires a real-keyboard check; no keyboard policy was changed by the mouse package.
- `evidence/routing-smoke.json`: generated by the routing script; its `trackingAreaQualified` flag explicitly stays false.
- `evidence/physical-settings-qualification.json`: user physically moved the mouse over and around protected Settings. Native routing increased from 33 to 628 (595 events), Flutter observed hover, and DOM counts stayed empty. After closing, leases returned to zero and WebView received a trusted wheel event without reloading.
- `evidence/physical-qualification.json`: generated only by `--physical`; the full multi-phase physical matrix has not been run. Physical hover for the URL variant and every gesture are not claimed by the Settings report.

Verified local stack: Flutter 3.44.6 / Dart 3.12.2. Package has 10 Dart tests and 11 standalone AppKit tests; lab has one HTTP harness test. The macOS Debug build succeeds. CocoaPods is used for `flutter_inappwebview_macos` because that dependency does not provide SwiftPM support; the new package supports both pod and SwiftPM registration.

## Repository layout

The package and this app are versioned together in [webview_modal_guard](https://github.com/DimitriSky/webview_modal_guard). Run this README's commands from `example/` after the initial `cd example`. Keep `path: ..` here so tests exercise the implementation in the same checkout. Consuming applications, including SimpleWebBrowser, should use the package's Git URL pinned to an immutable commit. Recheck the relevant Settings/URL scenarios in the consuming application; the lab Settings physical-input check is recorded separately from the broader matrix. The loopback server and probe remain confined to this example.
