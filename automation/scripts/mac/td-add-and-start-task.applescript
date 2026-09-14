-- Adds "<ClickUp title>: <ClickUp link>" as a Time Doctor task, sets its project via
-- the sidebar, and starts it. Mirrors scripts/windows/td-add-and-start-task.ps1's
-- proven-correct design (see TIMEDOCTOR_UIA_FINDINGS.md for why this is coordinate
-- automation at all, and ../ONBOARDING.md for the calibration process):
--   - Sidebar project selection by FORMULA (last-row Y + row height), not per-project
--     pixel lookup - only TD_SIDEBAR_PROJECT_ORDER needs updating per account.
--   - Foreground re-verified before EVERY click/paste, not just once at the start -
--     confirmed on Windows that focus can drift mid-sequence (the user actively using
--     another app) and a single check at the top of the script is not enough.
--   - Clipboard + keystroke paste, not per-character typing.
--
-- !!! UNCALIBRATED - DO NOT RUN FOR REAL UNTIL CALIBRATED IS SET TO true BELOW !!!
-- This was written in a Windows-only session with no Mac access, so every coordinate
-- below is a structural placeholder, not a measurement. Running it uncalibrated could
-- misclick in a real Time Doctor account exactly like the bugs this same design caught
-- (and fixed) on Windows during real testing. Calibration steps: ../ONBOARDING.md.
property CALIBRATED : true

property TD_WIN_X : 100
property TD_WIN_Y : 100
property TD_WIN_W : 1060
property TD_WIN_H : 791

-- Measured 2026-09-14 from a real screenshot (td-force-geometry-and-screenshot.applescript)
-- on this Mac. IMPORTANT: screencapture -R saves at native Retina resolution (2x here -
-- confirmed: 2120px/1060pt window width, 1582px/791pt height, both exactly 2.0), so pixel
-- coordinates read off the PNG were divided by 2 to get the point-space coordinates that
-- System Events "click at" actually needs. Re-derive with the same /2 step if re-measuring.
property TD_ADD_TASK_FIELD_X : 525
property TD_ADD_TASK_FIELD_Y : 159
property TD_ADD_START_BUTTON_X : 1013
property TD_ADD_START_BUTTON_Y : 159

-- Sidebar project selection by formula - see td-common.ps1's equivalent for the full
-- rationale.
-- Measured 2026-09-14: what first looked like a scrollbar thumb next to the highlighted
-- "meydan_directory" row turned out to be a selection-accent bar, not a scroll thumb -
-- confirmed by sending real CGEvent scroll-wheel events (td-scroll.js) at two different
-- points over the list and diffing before/after screenshots: zero pixel movement in the
-- sidebar either time. This account's full PROJECTS list is exactly the 10 rows visible
-- with no scrolling required (TD_SIDEBAR_SCROLL_X/Y are kept as a harmless no-op safety
-- net in case a future account has a longer list). Row height was derived from the
-- measured gap between the first (TD, pixel y=838) and last (VMS_Magid, pixel y=1543)
-- rows divided by 9 gaps, then /2 for Retina points: (1543-838)/9/2 = 39.17pt - this
-- matches independently spot-measuring meydan_directory's own row directly (615pt).
property TD_SIDEBAR_X : 300
property TD_SIDEBAR_LAST_ROW_Y : 772
property TD_SIDEBAR_ROW_HEIGHT : 39.17
property TD_SIDEBAR_SCROLL_X : 300
property TD_SIDEBAR_SCROLL_Y : 500
-- Real project names, top to bottom as shown in the sidebar, lowercase. Two names were
-- truncated on screen ("AI Personal Ass...", "Self Learning & ...") - filled in from the
-- matching ClickUp space/folder names seen in list_clickup_lists; unconfirmed character-
-- for-character but irrelevant to selecting "meydan_directory" (index 5 of 10, confirmed
-- exactly matches the independently-measured row position above).
property TD_SIDEBAR_PROJECT_ORDER : {"td", "all", "ai personal assistant", "cp-portal", "eyecentric", "meydan_directory", "pa", "self learning & r&d", "sena", "vms_magid"}

on assertForeground()
	tell application "System Events"
		set frontApp to name of first application process whose frontmost is true
	end tell
	if frontApp is "Time Doctor" then return

	tell application "Time Doctor" to activate
	delay 0.4
	tell application "System Events"
		set frontApp to name of first application process whose frontmost is true
	end tell
	if frontApp is not "Time Doctor" then
		error "Refusing to act: Time Doctor is not the foreground app (currently '" & frontApp & "') and could not be reclaimed. Coordinate-based automation is not safe to run blind - re-run once you're not actively using another app."
	end if
end assertForeground

on forceGeometry()
	tell application "Time Doctor" to activate
	delay 0.3
	tell application "System Events"
		if not (exists process "Time Doctor") then
			error "Time Doctor process not found. Is it running?"
		end if
		tell process "Time Doctor"
			if (count of windows) is 0 then
				error "Time Doctor has no open windows."
			end if
			set position of window 1 to {TD_WIN_X, TD_WIN_Y}
			set size of window 1 to {TD_WIN_W, TD_WIN_H}
			delay 0.3
		end tell
	end tell
	my assertForeground()
end forceGeometry

on scrollSidebarToBottom()
	my assertForeground()
	set scrollX to TD_WIN_X + TD_SIDEBAR_SCROLL_X
	set scrollY to TD_WIN_Y + TD_SIDEBAR_SCROLL_Y
	-- NOTE: "(container of (path to me)) as text" fails with "Can't make ... into type
	-- text" (-1700) on this macOS version - confirmed by real testing on 2026-09-14.
	-- Going through POSIX paths and shell dirname avoids the alias/HFS-text coercion.
	set scriptPosixPath to POSIX path of (path to me)
	set scriptDirPosix to do shell script "dirname " & quoted form of scriptPosixPath
	set scriptPath to scriptDirPosix & "/td-scroll.js"
	-- Large negative magnitude, well beyond any plausible list length, to guarantee
	-- hitting the bottom regardless of starting scroll position - same principle as
	-- the Windows -40-notch scroll. Real per-tick magnitude is unconfirmed (see
	-- td-scroll.js) - may need adjusting once tested for real.
	do shell script "osascript -l JavaScript " & (quoted form of scriptPath) & " " & scrollX & " " & scrollY & " -4000"
	delay 0.5
end scrollSidebarToBottom

-- NOTE: "tell application System Events to click at {x,y}" and "keystroke ... using
-- command down" both fail hard with "System Events got an error: osascript is not
-- allowed assistive access" (-25211) - confirmed by real testing on 2026-09-14, on
-- BOTH a remote-controlled session AND a genuinely local Terminal, and NOT fixed by
-- granting/resetting Accessibility or Automation/AppleEvents permissions for Terminal
-- or Visual Studio Code. The actual TCC log (log show --predicate 'process=="tccd"')
-- showed the real denied service is kTCCServicePostEvent ("does not allow prompting;
-- returning denied") - a stricter, non-promptable gate that System Events' "click at"/
-- "keystroke" hit specifically, distinct from the plain Accessibility checks that DID
-- succeed for window position/size (those are a different, promptable service).
-- Window management (forceGeometry, assertForeground's activate) is untouched here
-- because those calls kept working throughout.
--
-- FIX: shell out to `cliclick` (Homebrew, CGEvent-based, like td-scroll.js) instead of
-- System Events for the actual click/type actions - confirmed working live: a real
-- click landed a visible text cursor in Time Doctor's Add Task field with no TCC error.
property CLICLICK_PATH : "/opt/homebrew/bin/cliclick"

on clickAt(offsetX, offsetY)
	my assertForeground()
	-- cliclick requires integer coordinates - the sidebar row-height formula produces
	-- fractional Y values (e.g. 715.32), which fail with "Invalid Y axis coordinate"
	-- (confirmed by real testing 2026-09-14). Round here so callers can keep passing
	-- exact formula results.
	set targetX to round (TD_WIN_X + offsetX)
	set targetY to round (TD_WIN_Y + offsetY)
	do shell script CLICLICK_PATH & " c:" & targetX & "," & targetY
end clickAt

on typeText(theText)
	my assertForeground()
	do shell script CLICLICK_PATH & " t:" & (quoted form of theText)
end typeText

on selectSidebarProject(projectName)
	-- NOTE: a local variable named "key" collides with a reserved System Events term
	-- and fails with "Can't set key to ..." (-10006) - confirmed by real testing on
	-- 2026-09-14. Renamed to projKey.
	set projKey to my toLowerTrim(projectName)
	set idx to -1
	repeat with i from 1 to count of TD_SIDEBAR_PROJECT_ORDER
		if item i of TD_SIDEBAR_PROJECT_ORDER is projKey then
			set idx to i - 1 -- 0-based, matching the Windows implementation's indexing
			exit repeat
		end if
	end repeat
	if idx is -1 then
		set available to ""
		repeat with p in TD_SIDEBAR_PROJECT_ORDER
			set available to available & p & ", "
		end repeat
		error "Project '" & projectName & "' is not in the known sidebar order: " & available & ". Update TD_SIDEBAR_PROJECT_ORDER in this script with the real project list."
	end if
	set fromEnd to (count of TD_SIDEBAR_PROJECT_ORDER) - 1 - idx
	my scrollSidebarToBottom()
	set rowY to TD_SIDEBAR_LAST_ROW_Y - (fromEnd * TD_SIDEBAR_ROW_HEIGHT)
	my clickAt(TD_SIDEBAR_X, rowY)
	delay 0.5
end selectSidebarProject

on toLowerTrim(s)
	-- Shell-based rather than a manual AppleScript character loop - AppleScript string
	-- iteration semantics here are error-prone (a plain string isn't reliably
	-- iterable with "repeat with c in s" the way a list is), and this needs actual
	-- trimming too, not just case-folding.
	return do shell script "printf '%s' " & (quoted form of (s as text)) & " | tr '[:upper:]' '[:lower:]' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'"
end toLowerTrim

on run argv
	if (count of argv) is less than 2 then
		error "Usage: osascript td-add-and-start-task.applescript <task-title> <ticket-link> [project-name]"
	end if
	if not CALIBRATED then
		error "This script is not calibrated for this Mac/account yet (CALIBRATED is false). See ../ONBOARDING.md for the calibration steps - do not flip this to true without actually measuring real coordinates first."
	end if

	set taskTitle to item 1 of argv
	set ticketLink to item 2 of argv
	set projectName to ""
	if (count of argv) > 2 then set projectName to item 3 of argv
	set taskText to taskTitle & ": " & ticketLink

	my forceGeometry()

	if projectName is not "" then
		my selectSidebarProject(projectName)
	end if

	my clickAt(TD_ADD_TASK_FIELD_X, TD_ADD_TASK_FIELD_Y)
	delay 0.4
	my typeText(taskText)
	delay 0.4
	my clickAt(TD_ADD_START_BUTTON_X, TD_ADD_START_BUTTON_Y)
	delay 0.8

	return "RESULT_JSON: {\"success\":true,\"taskText\":\"" & taskText & "\",\"projectName\":\"" & projectName & "\"}"
end run
