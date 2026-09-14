-- STEP 2 of Mac automation. Adds "<ClickUp title>: <ClickUp link>" as a Time
-- Doctor task and starts it, using the fixed-window-geometry + coordinate-click
-- strategy proven on Windows (see TIMEDOCTOR_UIA_FINDINGS.md for why this is
-- coordinate-based rather than named-element automation).
--
-- DO NOT USE FOR REAL until TD_ADD_TASK_FIELD_*/TD_ADD_START_BUTTON_* below have
-- been replaced with real measurements from td-force-geometry-and-screenshot.applescript's
-- output - the values here are placeholders copied from the Windows calibration and are
-- very likely wrong (macOS window chrome/title bar differs from Windows).
--
-- PREREQUISITE: Accessibility permission granted, same as the other scripts.
--
-- USAGE:
--   osascript td-add-and-start-task.applescript "Server deployment and Owner side call routing" "https://app.clickup.com/t/3xxxxx"

-- Keep these in sync with td-force-geometry-and-screenshot.applescript
property TD_WIN_X : 40
property TD_WIN_Y : 40
property TD_WIN_W : 1060
property TD_WIN_H : 880

-- PLACEHOLDER - re-measure on the real Mac app before relying on this.
property TD_ADD_TASK_FIELD_X : 450
property TD_ADD_TASK_FIELD_Y : 232
property TD_ADD_START_BUTTON_X : 996
property TD_ADD_START_BUTTON_Y : 232

on run argv
	if (count of argv) is less than 2 then
		error "Usage: osascript td-add-and-start-task.applescript <task-title> <ticket-link>"
	end if
	set taskTitle to item 1 of argv
	set ticketLink to item 2 of argv
	set taskText to taskTitle & ": " & ticketLink

	tell application "System Events"
		if not (exists process "Time Doctor") then
			error "Time Doctor process not found. Is it running?"
		end if
		tell process "Time Doctor"
			set frontmost to true
			if (count of windows) is 0 then
				error "Time Doctor has no open windows."
			end if
			set position of window 1 to {TD_WIN_X, TD_WIN_Y}
			set size of window 1 to {TD_WIN_W, TD_WIN_H}
			delay 0.5
		end tell
	end tell

	set fieldX to TD_WIN_X + TD_ADD_TASK_FIELD_X
	set fieldY to TD_WIN_Y + TD_ADD_TASK_FIELD_Y
	set btnX to TD_WIN_X + TD_ADD_START_BUTTON_X
	set btnY to TD_WIN_Y + TD_ADD_START_BUTTON_Y

	tell application "System Events"
		click at {fieldX, fieldY}
		delay 0.4
		set the clipboard to taskText
		delay 0.2
		keystroke "v" using command down
		delay 0.4
		click at {btnX, btnY}
	end tell

	delay 0.8
	return "Clicked Add Task field at (" & fieldX & "," & fieldY & ") and Add+Start button at (" & btnX & "," & btnY & ") with text: " & taskText
end run
