# Setting this up on a teammate's own laptop

This is a **per-user local instance** (see README.md) — there's no shared server.
Each person runs their own full copy of this code on their own machine (Windows or
Mac), with their own credentials, controlling their own logged-in Time Doctor app.
Nothing here is Rudrik-specific in the code itself; it's all in each person's own
`.env` and one recalibration step below.

**This document is written from the Windows setup, which is proven working.** A
separate **Mac section at the bottom** covers the same steps for Mac — but Mac's
Time Doctor automation itself is unverified (written without any real Mac to test
against; see `../TIMEDOCTOR_UIA_FINDINGS.md`). Everything else (ClickUp side, MCP
registration, workspace config) is identical cross-platform.

## 0. Get the code onto their machine

Private repo, already set up: https://github.com/Rudrik-TechEniac/clickup-timedoctor-automation

They need to be added as a collaborator first (it's private) - ask Rudrik, or
whoever has admin on it, to add their GitHub account under Settings → Collaborators
on that repo. Then:

```bash
git clone https://github.com/Rudrik-TechEniac/clickup-timedoctor-automation.git
cd clickup-timedoctor-automation
```

`node_modules/`, `dist/`, `.env`, and `data/` are all git-ignored - each person's
`npm install`/`.env`/`npm run build` (steps below) regenerates or creates their own.

## Why does this need to track state at all?

Time Doctor itself can't be trusted as the source of truth: its automation can
silently fail, the app can be closed, and it doesn't know anything about ClickUp
ticket IDs - that mapping only exists in our own system. A local JSON file
(`data/state.json`, created automatically, no setup needed) is what actually
tracks:
- **What's currently active** right now, so `get_current_ticket` / `stop_ticket`
  work correctly.
- **Start/stop timestamps and accumulated duration per ticket** - Time Doctor alone
  can't answer "how long have I worked on ticket X across all sessions."
- **An event log** for debugging when something goes wrong.

Without it, "switch ticket" and accurate time totals wouldn't be possible. No
database server to install - this is one person, one machine, one file.

## 1. Prerequisites on their machine

- **Node.js 20+** — https://nodejs.org
- **Time Doctor desktop app** — installed and logged into *their own* Time Doctor
  account, kept open during use (this automation drives that real app - it needs
  to actually be running).
- **Their own ClickUp Personal API Token** — see README.md Setup step 1. It must be
  their own login, not shared - the token determines whose identity the automation
  acts as.

## 2. Configure

1. `cd automation`, `npm install`
2. Copy `.env.example` → `.env` and fill in:

| Variable | What it is | How to get it |
|---|---|---|
| `CLICKUP_API_TOKEN` | Their own ClickUp identity | ClickUp → their avatar (bottom-left) → **Settings** → **Apps** → **API Token** → **Generate**. Must be their own login, not shared - this determines whose identity the automation acts as. |
| `CLICKUP_TEAM_ID` | The company workspace ID (same for everyone) | Already known for this company: `3371638`. To find it independently: `curl -H "Authorization: <their token>" https://api.clickup.com/api/v2/team` |
| `CLICKUP_ASSIGNEE_USER_ID` | **Their own** ClickUp user ID (scopes ticket search to their own work, not Rudrik's) | `curl -H "Authorization: <their token>" https://api.clickup.com/api/v2/user` → `user.id` in the response |
| `TD_SCRIPTS_DIR` | Absolute path to *their own* `automation\scripts\windows` folder | Wherever the code ends up on their machine - will differ from Rudrik's path |
| `TD_AUTOMATION_DISABLED` | Safety switch | `true` while testing ClickUp-only first, `false` once confirmed working, for real Time Doctor automation |
| `STATUS_IN_PROGRESS` / `STATUS_IN_REVIEW` / `STATUS_TODO` | Real ClickUp status names used by the automatic start/stop flow | Check a real ticket's status dropdown in ClickUp, or once their token is set, ask Claude to call `get_available_statuses` on any ticket - status names can have surprising quirks like trailing spaces (`update_ticket_status`/`get_available_statuses` handle that robustly, but these `.env` defaults still need to roughly match) |
| `CLICKUP_WEBHOOK_SECRET` | Only needed if registering the ClickUp webhook | Optional - leave blank unless wiring up `/webhooks/clickup` |
| `PORT` | Only needed if running the HTTP server (webhooks/remote MCP) | Not needed at all for Claude-Code-only usage (stdio MCP) |

The three actually **required** for a Claude-Code-only setup (no webhooks, no HTTP
server): `CLICKUP_API_TOKEN`, `CLICKUP_TEAM_ID`, `TD_SCRIPTS_DIR`.
Everything else has a working default or isn't needed for this usage mode. No
database setup step - state lives in `data/state.json`, created automatically.

3. `npm run build`

## 3. Recalibrate the Time Doctor sidebar project list (the one real per-person step)

`scripts/windows/td-common.ps1` selects a sidebar project by **formula**, not a
per-project pixel lookup: rows are evenly spaced (~48px), so a row's position is
computed from `TD_SIDEBAR_LAST_ROW_Y` (the last row's Y once scrolled to the bottom)
counting upward by how far the target project is from the end of
`TD_SIDEBAR_PROJECT_ORDER`. The row height and last-row position are app-chrome
constants that transfer across machines on the same Time Doctor version - **only
`TD_SIDEBAR_PROJECT_ORDER` (the actual list of project names) is person/company-specific.**

If the company Time Doctor account shows the same shared Projects list to everyone
(common for a company-wide plan), this may already work as-is for a teammate - worth
trying first. If their sidebar has a different set of projects, updating it needs
**no pixel measuring at all**, just reading names off a screenshot:

1. Open their Time Doctor app, make sure it's logged in and visible.
2. Run: `powershell -File scripts\windows\td-screenshot-only.ps1 -OutFile calibrate.png`
   (safe - this only screenshots, never clicks anything).
3. Open `calibrate.png`, scroll the sidebar to the bottom of the PROJECTS list first
   if needed, then just read the project names top-to-bottom as they appear (no
   measuring - Claude can do this directly from the screenshot if asked).
4. Replace `$Script:TD_SIDEBAR_PROJECT_ORDER` in `td-common.ps1` with that list, in
   that same order, lowercased.

**Limitation:** this only reaches a project within the visible window (~8 rows)
counting up from the bottom of a long list. A project far from the end of a much
longer list isn't reachable by the formula alone - that edge case would need
`TD_SIDEBAR_LAST_ROW_Y`/`TD_SIDEBAR_ROW_HEIGHT` re-verified and possibly a scroll
step added for that specific project, not just an array update.

Everything else in `td-common.ps1` (window size/position, Add Task field, Add+Start
button, Stop button) is also app-chrome, not data-dependent - it should transfer as-is
as long as they're on the same Time Doctor version (v3.12.16 at time of writing).
If a Time Doctor update moves things, re-measure the same way.

## 4. Register the MCP server with Claude Code

```
claude mcp add -s user clickup-timedoctor -- node "<their-full-path>\automation\dist\mcpStdioEntry.js"
```

`-s user` makes it available in every Claude Code session on their machine, not
just one project folder. Verify with `claude mcp get clickup-timedoctor` — should
show `✔ Connected`.

## 5. Using it

Same as README: first message in a new Claude Code session, ask Claude to show
their ClickUp lists and set up the workspace (`list_clickup_lists` +
`configure_workspace`) - this is per-session, not saved, so it happens once each
time they start a new chat. After that, natural language: "start my next ticket",
"stop this ticket", "mark X complete", etc.

## What does NOT need to be redone per person

- The code itself - no per-user logic changes needed, it's all config-driven.
- ClickUp workspace/team id.
- Most of the Time Doctor pixel calibration (app-chrome positions).

## What's still open company-wide

- Mac's Time Doctor automation is now calibrated and verified live (2026-09-14, see
  `TIMEDOCTOR_UIA_FINDINGS.md`'s Mac section) - one real finding for future
  teammates setting up on a different Mac: plain AppleScript `System Events` clicks
  are blocked outright by macOS (`kTCCServicePostEvent` denial, not fixable via the
  normal Accessibility permission toggle), so both action scripts now depend on
  `cliclick` (`brew install cliclick`) instead. Add that as a Mac prerequisite below.
  The rest of a new person's calibration (measuring their own window/button/sidebar
  coordinates) still needs to be redone per-Mac the same way - only the "which
  click mechanism works at all" finding transfers.
- If this needs to scale beyond a handful of people, consider actually setting up
  the git repo (step 0) rather than copying folders by hand each time.

---

# Mac setup

Everything in steps 0, 1 (except the OS-specific bits below), 2, 4, and 5 above is
identical on Mac - same `npm install`/`.env`/`npm run build`, same
`claude mcp add` registration, same natural-language usage once configured. This
section only covers what's different: prerequisites, and the Time Doctor
calibration (step 3), which is a different mechanism entirely on Mac and - unlike
the Windows version - **has never been run for real**.

## Mac prerequisites

- **Node.js 20+** — https://nodejs.org
- **Time Doctor desktop app for Mac**, installed and logged into their own account.
- **Their own ClickUp Personal API Token** — same as Windows, see the main `.env`
  table above.
- **`cliclick`** — `brew install cliclick`. Required: plain AppleScript `System
  Events` clicks/keystrokes are blocked outright on macOS by a TCC service
  (`kTCCServicePostEvent`) that isn't fixable via the normal Accessibility
  permission toggle - confirmed by real testing 2026-09-14, see
  `TIMEDOCTOR_UIA_FINDINGS.md`'s Mac section. Both action scripts shell out to
  `cliclick` (hardcoded at `/opt/homebrew/bin/cliclick` - update `CLICLICK_PATH` in
  both `.applescript` files if a different Mac's Homebrew prefix differs, e.g.
  Intel Macs default to `/usr/local/bin`).
- **Grant Accessibility permission**: System Settings → Privacy & Security →
  Accessibility. Exactly which process needs this grant is genuinely unconfirmed
  (Terminal, iTerm, or the Node.js binary itself, depending on how it's launched) -
  if automation silently fails, check/add all of them. Note this only covers
  window move/resize and general Accessibility API calls, NOT the click/keystroke
  simulation itself (that's what `cliclick` works around) - see
  `TIMEDOCTOR_UIA_FINDINGS.md`'s Mac section for the full finding.
- `TD_SCRIPTS_DIR` in `.env` should point at `automation/scripts/mac` (not
  `scripts/windows`).

## Mac Time Doctor calibration (required - scripts refuse to run without it)

Both `automation/scripts/mac/td-add-and-start-task.applescript` and
`td-stop-current-task.applescript` start with `property CALIBRATED : false` and will
error out immediately if run as-is. This is deliberate: none of the pixel
coordinates in them have been measured on a real Mac, and running with guessed
coordinates risks a real misclick in a real Time Doctor account (this happened more
than once during Windows testing, even with real measurements - guessed ones would
be worse).

1. Open Time Doctor on the Mac, log in, make sure the main dashboard window (not
   just a menu-bar icon) is visible.
2. Run: `osascript automation/scripts/mac/td-force-geometry-and-screenshot.applescript calibrate.png`
   (safe - forces window geometry and screenshots it, but never clicks anything).
3. Open `calibrate.png` and measure real pixel coordinates for:
   - The "Add Task" field, the combined Add+Start button, and the Stop button
     (same UI elements measured on Windows - see `TIMEDOCTOR_UIA_FINDINGS.md`'s
     Windows section for what these look like/where they are in the app, though the
     exact pixel numbers will differ - Mac's window chrome, title bar height, and
     lack of an in-window File/Edit menu bar (it's in the system menu bar on Mac)
     mean these are NOT the same numbers as Windows).
   - The sidebar PROJECTS list: measure the Y position of the last visible row once
     scrolled to the bottom (`TD_SIDEBAR_LAST_ROW_Y`) and the pixel gap between rows
     (`TD_SIDEBAR_ROW_HEIGHT`) - same formula-based approach as Windows (see
     `td-common.ps1`'s equivalent), just needs its own real measurements.
   - List the real project names in sidebar order into `TD_SIDEBAR_PROJECT_ORDER`.
4. **Test the sidebar scroll separately before trusting it** - `td-scroll.js` (the
   JXA scroll-wheel helper `td-add-and-start-task.applescript` calls internally) has
   never been run for real. Its scroll magnitude (`-4000` in the script) is a guess;
   watch whether it actually reaches the bottom of the projects list, and adjust if
   not.
5. Update all the `property` values (window position/size, field/button offsets,
   sidebar constants, project order) at the top of both `.applescript` files with
   the real measured numbers.
6. **Only after all of that**, flip `property CALIBRATED : false` to `true` in both
   files.
7. Test for real: `osascript automation/scripts/mac/td-add-and-start-task.applescript "Test Task" "https://example.com/test" "SomeRealProjectName"`,
   confirm visually it created+started the task under the right project, then
   `osascript automation/scripts/mac/td-stop-current-task.applescript` to confirm
   stop works. Expect to create real (deletable) test entries in the real account
   while doing this - same as happened during Windows testing.
8. Update `TIMEDOCTOR_UIA_FINDINGS.md`'s Mac section and this file with the real
   verdict once tested, the same way the Windows section documents what was actually
   found.
