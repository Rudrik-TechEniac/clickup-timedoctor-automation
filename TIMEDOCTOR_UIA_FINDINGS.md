# Time Doctor Desktop UI-Automation Feasibility — Findings

## Summary

| Platform | Verdict | Confidence |
|---|---|---|
| Windows — named-element UIA control | **Not viable** | High — tested directly, multiple ways, conclusive negative |
| Windows — coordinate-based automation | **Viable, working** | Confirmed end-to-end: add task + start, and stop, both tested live against the real app |
| Mac — `System Events` coordinate clicks | **Not viable** | High — tested directly and conclusive: window move/resize via System Events works, but `click at`/`keystroke` fail hard with "osascript is not allowed assistive access" (kTCCServicePostEvent, a stricter non-promptable TCC gate). Reproduced identically on a remote-controlled session AND a genuinely local Terminal; NOT fixed by granting or resetting Accessibility/Automation permissions for Terminal or the calling app. |
| Mac — `cliclick` (Homebrew, CGEvent-based) coordinate clicks | **Viable, working** | Confirmed end-to-end 2026-09-14 against the real live account: add task + start (with sidebar project selection), and stop, both tested live and visually verified via screenshot. Two real script bugs also found and fixed by this testing (see Mac section below). |

**Bottom line:** Time Doctor's own controls are not reachable via UI Automation (see "Windows — UIA Detailed Results" below), but **coordinate-based mouse click + clipboard paste automation works and was verified live** against the real running app: it correctly (1) types `"<ClickUp title>: <ClickUp link>"` into the "Add Task" field and clicks the row's Play button to create+start a task, which also auto-stops whatever was previously running, and (2) clicks the banner's Stop button to stop the active task. This directly matches the actual product's workflow, shown by the user (screenshot): Time Doctor here isn't a single always-on timer with a task dropdown — it's a **list of tasks, each individually startable**, and starting one auto-stops any other running one. This is a better fit for "switch ticket" than originally assumed (no separate stop-then-start needed — starting the new task's row does both).

**Caveat — this is coordinate-based, not name-based automation.** It clicks fixed positions (as fractions of the window's current size), calibrated against one specific window layout at v3.12.16. It will break if: the window is resized differently than expected, the app UI changes in an update, or the "Add Task" row's layout shifts. Scripts: `scratchpad/windows/td-add-and-start-task.ps1` and `scratchpad/windows/td-stop-current-task.ps1`.

**⚠️ Real data created during testing:** two test tasks ("Error validation implementation" and "Error validation implementation 2", with fake ClickUp links) were created in the **real, live company Time Doctor account** during verification and are still sitting in the Current Tasks list with a few seconds/minutes of tracked time each. These should be deleted (or told apart from real work) before this is relied on for real reporting — flag to the user to clean these up, or confirm whether the Time Doctor API supports task deletion.

---

## Windows — Coordinate Automation (the part that actually works)

**Discovery:** the app doesn't have one global timer + a project dropdown — it has a per-task list (visible in Current/Next/Future Tasks folders), each row with its own Play button, plus an "Add Task" text field + a combined Add-and-Start Play button at the top of the list, and a big Stop button in the green/gray banner once something is running. Starting any task's Play button automatically stops whichever task was previously running (single active tracked task, enforced by the app itself) — so "switch ticket" is just "start the new one," no separate stop step required.

**How the scripts work:**
1. `td-add-and-start-task.ps1 -TaskTitle "..." -TicketLink "..."` — finds the real dashboard window (by title containing "Company Time", distinguishing it from the small always-on "Activity Bar" widget which shares the process), restores/foregrounds it, reads its actual on-screen rectangle (with `SetProcessDPIAware` to avoid a DPI-scaling coordinate mismatch that initially corrupted screenshots), clicks the "Add Task" field, pastes `"<title>: <link>"` via the clipboard (avoids `SendKeys` special-character issues with URLs), and clicks the Add+Start button. Coordinates are stored as **fractions** of a calibration window (1060×880) so moderate resizing is tolerated.
2. `td-stop-current-task.ps1` — same window-finding logic, clicks the Stop button in the banner.
3. Both take before/after screenshots for verification since there's no UIA/API way to confirm success — verification here was visual (screenshots matched expected state: new task highlighted green with a running timer; after stop, banner turns gray with a Play icon and the task's accumulated time is preserved).

**Verified live, twice each:** add+start correctly created a new task, started its timer from 0, and stopped the previously-running task (preserving its accumulated time, `06:36:55` unaffected by the switch); stop correctly halted the running timer.

## Windows — Detailed Results (why plain UIA doesn't work)

**Setup:** Time Doctor v3.12.16 was already installed and running (`com.timedoctor.desktop`). Multiple `Time Doctor.exe` processes were present (Electron main + helper processes), main window class `Chrome_WidgetWin_1` — confirming this is an **Electron** app.

**Round 1 — original running instance:**
- **`td-uia-dump.ps1`** dumped the UIA tree of the main window (`FromHandle` + recursive `FindAll(Children)`). Result: **one node (the window itself), zero children**, even after restoring from minimized, waiting and re-querying, and starting **Windows Narrator** (confirmed running via `Get-Process`) — the standard way to force Chromium's full accessibility tree on. Still zero elements.
- **`enum-children.ps1`** found **zero native child HWNDs** under the main window.
- Tray probes (`td-tray-probe.ps1`/`2.ps1`) found no "Time Doctor"-named element anywhere in the desktop UIA tree (inconclusive on its own — Windows 11's tray UI uses non-obvious window classes — but consistent with the rest).

**Root-cause detour:** attempting to relaunch the app to test the `--force-renderer-accessibility` Chromium flag initially failed silently — the relaunched process started and exited immediately every time. Cause: this automation session's shell has `ELECTRON_RUN_AS_NODE=1` set (inherited from the Node/Electron tooling Claude Code itself runs on), which any child Electron process inherits, causing it to run its main.js as a plain Node script instead of booting the Electron GUI runtime. Fixed by launching via `System.Diagnostics.Process` with that variable explicitly removed from the child's environment. Worth remembering for any future automation that shells out to launch GUI apps from this kind of environment.

**Round 2 — after a clean relaunch (env fixed, no special flags):** the tree suddenly went from "one node, zero children" to a populated **native window structure**: the real "Activity Bar" widget window (575×64px) and the full dashboard window were both found, each with a `Chrome_RenderWidgetHostHWND` child pane — real progress compared to round 1. Best guess: Narrator having run at all earlier left some system-wide "assistive technology present" state active, which a *freshly launched* process picks up at startup (apps typically check once at launch, not continuously) — the original long-running instance never got the chance to. Unconfirmed as the exact mechanism, but empirically repeatable.

**Round 3 — relaunch with `--force-renderer-accessibility` added:** still only reached the same native `Chrome_RenderWidgetHostHWND` pane, with **zero children inside it** — i.e., Blink's actual web-content accessibility tree (the layer that would expose real Start/Stop/task-dropdown buttons) never populated, across multiple retries with delays up to several seconds. This is the layer that actually matters — Start/Stop and task-selection are React/DOM controls rendered inside that pane, not native Win32 controls.

**Conclusion:** across three different activation strategies (screen reader, fresh relaunch, explicit force-accessibility flag), Windows UIA consistently fails to expose the actual interactive controls inside Time Doctor's renderer. The outer native window/pane structure is visible, but the layer with real buttons is not. This is a firmer negative than round 1 alone — it rules out "just needed a screen reader" or "just needed the standard flag" as the fix.

**What would be left to try, if this needs to be revisited:** coordinate-based mouse-click automation (`SendInput` at fixed screen coordinates) instead of named-element UIA calls. Intentionally not pursued — flagged in the plan as fragile (breaks on window resize/move/DPI change/app update) and not worth building on without stronger justification. If Time Doctor ever ships with accessibility genuinely enabled, this test should be re-run.

**Housekeeping note:** this investigation required killing and relaunching the real Time Doctor app on this machine several times (each relaunch showed "Company Time" tracking resumed normally). It was left in its normal, clean, logged-in state (no debug flags) at the end.

## Mac — Status

**UPDATE 2026-09-14: calibrated and verified live, end-to-end, against the real
account.** Everything below this note originally described the pre-verification
state (written blind, no Mac access) - kept for history, but superseded by this
summary of what real testing on a real Mac (v3.12.16) actually found:

- **Window management works via plain AppleScript/System Events** exactly as
  originally written: `set position`/`set size` of `window 1`, and foreground
  activation/checks (`assertForeground`, `forceGeometry`) all succeeded with no
  changes needed.
- **Simulated clicks and keystrokes via System Events do NOT work and cannot be
  made to** - `tell application "System Events" to click at {x,y}` and `keystroke
  ... using command down` both fail with "osascript is not allowed assistive
  access" (-25211). The real TCC log (`log show --predicate 'process=="tccd"'`)
  showed the actual denied service is `kTCCServicePostEvent`, logged explicitly as
  "does not allow prompting; returning denied" - a stricter, non-interactive gate,
  distinct from the plain `kTCCServiceAccessibility` checks that DID succeed for
  window move/resize. This reproduced identically across a remote-controlled
  session AND a genuinely local Terminal window, and granting or `tccutil reset`-ing
  Accessibility/Automation(AppleEvents) permissions for Terminal, `osascript`, and
  Visual Studio Code all had no effect. Root cause is believed to be that this
  particular TCC service simply isn't grantable via the normal per-app Accessibility
  prompt/toggle on this macOS version, not a misconfiguration.
- **Fix: `cliclick`** (Homebrew: `brew install cliclick`), a small CLI that posts
  clicks/keystrokes via the same lower-level `CGEventPost` mechanism `td-scroll.js`
  already used (which never hit this wall) rather than going through System Events'
  higher-level UI-scripting path. Both action scripts now shell out to it
  (`CLICLICK_PATH`, `c:x,y` for clicks, `t:text` for typing) instead of using
  `click at`/`keystroke`. Confirmed working live with no TCC error.
- **Two more real bugs found and fixed by this testing**, unrelated to the above:
  a local variable named `key` collides with a reserved System Events term and
  fails with "Can't set key to ..." (-10006) (renamed to `projKey`); and
  `(container of (path to me)) as text` fails with "Can't make ... into type text"
  (-1700) on this macOS version (rewritten via `POSIX path of` + shell `dirname`).
  cliclick also requires integer coordinates - the sidebar row-height formula
  produces fractions (e.g. `715.32`), fixed by rounding in `clickAt`.
- **Sidebar project list**: what first looked like a scrollbar thumb (implying a
  much longer, unscanned list) turned out to be the selection-accent bar next to
  the highlighted row, confirmed by sending real scroll events and diffing
  before/after screenshots (zero movement). This account's full list is exactly the
  10 visible rows; `TD_SIDEBAR_PROJECT_ORDER`/`TD_SIDEBAR_LAST_ROW_Y`/
  `TD_SIDEBAR_ROW_HEIGHT` are measured and confirmed (formula-computed row position
  for `meydan_directory` matched an independent direct measurement exactly).
- **Verified live, end-to-end**: add+start correctly created a new task under the
  right project (sidebar selection included) and started its timer from 0, stopping
  the previously-running task and preserving its accumulated time; stop correctly
  halted the running timer, leaving it resumable. Both `CALIBRATED` properties are
  now `true`.
- **Real data created during this verification**: a test task named "CALIBRATION
  TEST - safe to delete" (with a fake `https://example.com/calibration-test` link)
  was created in the real, live company Time Doctor account under `meydan_directory`
  and has a few seconds of tracked time. Flagged for cleanup, same as the Windows
  verification's equivalent note above.

Original pre-verification notes (kept for history):

**Design carried over from the proven Windows implementation** (same architecture,
translated to AppleScript/JXA):
- Coordinate-based automation via `click at {x,y}` (System Events) — real, current,
  confirmed-existing AppleScript feature (though undocumented by Apple itself).
- Window forced to a fixed size/position before every action (`set position`/`set size`
  of `window 1` via System Events).
- **Foreground re-verified before every single click and paste**, not just once at the
  start — the exact fix the Windows focus-drift bug required. `assertForeground()` in
  each script checks `first application process whose frontmost is true` and
  re-activates if it's not Time Doctor, erroring out rather than proceeding blind if it
  still can't reclaim focus.
- **Sidebar project selection by formula** (last-row Y + row height), not a hardcoded
  pixel per project name — the fix the Windows wrong-project bug required. Only
  `TD_SIDEBAR_PROJECT_ORDER` (the actual project name list) needs to be
  account-specific; the row-height/last-row-Y constants are meant to be app-chrome,
  transferable across Mac machines the same way they are on Windows.
- A pure screenshot-only calibration/inspection script with **no click at all**
  (`td-force-geometry-and-screenshot.applescript`) — the fix for the blind-click bug
  that once accidentally started a real Time Doctor task on Windows.
- **A hard `CALIBRATED = false` guard** at the top of both action scripts
  (`td-add-and-start-task.applescript`, `td-stop-current-task.applescript`) that
  refuses to run at all until manually flipped to `true` — added specifically because
  none of the coordinates have been measured on a real Mac, and guessing here risks the
  exact kind of real-account misclick that happened multiple times during Windows
  testing.

**One genuinely new problem Mac has that Windows didn't:** AppleScript's System Events
has no native scroll-wheel action at all (confirmed via research — `click at {x,y}`
exists, nothing equivalent for scrolling exists). Worked around with a separate JXA
(JavaScript for Automation) helper, `td-scroll.js`, using the CoreGraphics
`CGEventCreateScrollWheelEvent` API directly via JXA's ObjC bridge — this is a real,
documented mechanism, but the actual scroll magnitude needed (how far is "definitely
past the end of the list") is unconfirmed; the Windows equivalent's magnitude
(40 wheel notches) was itself empirically chosen after testing, not calculated.

**Also unconfirmed:** which process actually needs the Accessibility permission grant
(Terminal, iTerm, or the Node.js binary itself if this runs via `child_process` from
the MCP server) — research found this is a known point of confusion even in Apple's
own ecosystem (TCC behavior for spawned child processes isn't formally documented),
not something specific to this project.

**Calibration steps** (needed before `CALIBRATED` can honestly be set to `true`):
see `automation/ONBOARDING.md`'s Mac section.

---

## Impact on the broader project plan

Windows CAN drive live Time Doctor control after all, via coordinate automation rather than the API or UIA. The MCP+backend architecture (Node/TS, MCP server) treats Time Doctor as genuinely controllable on Windows: when a ClickUp ticket starts, the backend shells out to `td-add-and-start-task.ps1` with the ticket's title+link; our local work-session records (a JSON file, not a database - see README) remain the authoritative source of truth (in case a click fails or the window layout drifts), and Time Doctor's own state is treated as best-effort/reconciled rather than blindly trusted. Given the fragility of coordinate automation, the backend verifies success where it can and logs everything rather than assuming every click lands. Mac support now has a full parallel implementation with the same design - see above - but is still unverified.
