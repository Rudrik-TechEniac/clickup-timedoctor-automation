-- Stops the currently running Time Doctor task by clicking the banner's Stop button.
-- Same design/caveats as td-add-and-start-task.applescript - see that file's header.
--
-- !!! UNCALIBRATED - DO NOT RUN FOR REAL UNTIL CALIBRATED IS SET TO true BELOW !!!
property CALIBRATED : false

property TD_WIN_X : 100
property TD_WIN_Y : 100
property TD_WIN_W : 1060
property TD_WIN_H : 880

-- PLACEHOLDER - re-measure on a real Mac screenshot.
property TD_STOP_BUTTON_X : 996
property TD_STOP_BUTTON_Y : 137

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
		error "Refusing to act: Time Doctor is not the foreground app (currently '" & frontApp & "') and could not be reclaimed."
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

on clickAt(offsetX, offsetY)
	my assertForeground()
	set targetX to TD_WIN_X + offsetX
	set targetY to TD_WIN_Y + offsetY
	tell application "System Events" to click at {targetX, targetY}
end clickAt

on run argv
	if not CALIBRATED then
		error "This script is not calibrated for this Mac/account yet (CALIBRATED is false). See ../ONBOARDING.md for the calibration steps."
	end if

	my forceGeometry()
	my clickAt(TD_STOP_BUTTON_X, TD_STOP_BUTTON_Y)
	delay 0.8

	return "RESULT_JSON: {\"success\":true}"
end run
