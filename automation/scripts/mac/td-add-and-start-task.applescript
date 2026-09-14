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
property CALIBRATED : false

property TD_WIN_X : 100
property TD_WIN_Y : 100
property TD_WIN_W : 1060
property TD_WIN_H : 880

-- Offsets from the window's top-left corner. PLACEHOLDERS - re-measure on a real Mac
-- screenshot (scripts/mac/td-force-geometry-and-screenshot.applescript) the same way
-- the Windows values were measured; macOS window chrome differs from Windows so these
-- will NOT be the same numbers.
property TD_ADD_TASK_FIELD_X : 450
property TD_ADD_TASK_FIELD_Y : 232
property TD_ADD_START_BUTTON_X : 996
property TD_ADD_START_BUTTON_Y : 232

-- Sidebar project selection by formula - see td-common.ps1's equivalent for the full
-- rationale. PLACEHOLDERS, same caveat as above.
property TD_SIDEBAR_X : 180
property TD_SIDEBAR_LAST_ROW_Y : 847
property TD_SIDEBAR_ROW_HEIGHT : 48
property TD_SIDEBAR_SCROLL_X : 180
property TD_SIDEBAR_SCROLL_Y : 500
-- Real project names, in the order Time Doctor's sidebar shows them (alphabetical,
-- "All" pinned first) - lowercase. Replace with the real list for the account this
-- runs under.
property TD_SIDEBAR_PROJECT_ORDER : {"all", "ai personal", "cp-portal", "eyecentric", "khalil_voice", "pa", "self learning", "sena"}

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
	set myFolder to (container of (path to me)) as text
	set scriptPath to POSIX path of (myFolder & "td-scroll.js")
	-- Large negative magnitude, well beyond any plausible list length, to guarantee
	-- hitting the bottom regardless of starting scroll position - same principle as
	-- the Windows -40-notch scroll. Real per-tick magnitude is unconfirmed (see
	-- td-scroll.js) - may need adjusting once tested for real.
	do shell script "osascript -l JavaScript " & (quoted form of scriptPath) & " " & scrollX & " " & scrollY & " -4000"
	delay 0.5
end scrollSidebarToBottom

on clickAt(offsetX, offsetY)
	my assertForeground()
	set targetX to TD_WIN_X + offsetX
	set targetY to TD_WIN_Y + offsetY
	tell application "System Events" to click at {targetX, targetY}
end clickAt

on pasteText(theText)
	my assertForeground()
	set the clipboard to theText
	delay 0.2
	my assertForeground()
	tell application "System Events" to keystroke "v" using command down
end pasteText

on selectSidebarProject(projectName)
	set key to my toLowerTrim(projectName)
	set idx to -1
	repeat with i from 1 to count of TD_SIDEBAR_PROJECT_ORDER
		if item i of TD_SIDEBAR_PROJECT_ORDER is key then
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
	my pasteText(taskText)
	delay 0.4
	my clickAt(TD_ADD_START_BUTTON_X, TD_ADD_START_BUTTON_Y)
	delay 0.8

	return "RESULT_JSON: {\"success\":true,\"taskText\":\"" & taskText & "\",\"projectName\":\"" & projectName & "\"}"
end run
