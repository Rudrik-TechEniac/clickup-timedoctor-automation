-- Stops the currently running Time Doctor task by clicking the banner's Stop button.
-- Same placeholder-calibration caveat as td-add-and-start-task.applescript applies.
--
-- USAGE:
--   osascript td-stop-current-task.applescript

property TD_WIN_X : 40
property TD_WIN_Y : 40
property TD_WIN_W : 1060
property TD_WIN_H : 880

-- PLACEHOLDER - re-measure on the real Mac app before relying on this.
property TD_STOP_BUTTON_X : 996
property TD_STOP_BUTTON_Y : 137

on run
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

	set btnX to TD_WIN_X + TD_STOP_BUTTON_X
	set btnY to TD_WIN_Y + TD_STOP_BUTTON_Y

	tell application "System Events"
		click at {btnX, btnY}
	end tell

	delay 0.5
	return "Clicked Stop button at (" & btnX & "," & btnY & ")"
end run
