-- Stops the currently running Time Doctor task by clicking the banner's Stop button.
-- Same design/caveats as td-add-and-start-task.applescript - see that file's header.
--
-- !!! UNCALIBRATED - DO NOT RUN FOR REAL UNTIL CALIBRATED IS SET TO true BELOW !!!
property CALIBRATED : true

property TD_WIN_X : 100
property TD_WIN_Y : 100
property TD_WIN_W : 1060
property TD_WIN_H : 791

-- Measured 2026-09-14 from a real screenshot, same /2 Retina-pixel-to-point conversion
-- as td-add-and-start-task.applescript - this is the big red Stop button in the top
-- banner (not a per-row play/stop icon).
property TD_STOP_BUTTON_X : 1010
property TD_STOP_BUTTON_Y : 82

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

-- NOTE: System Events "click at" fails with "osascript is not allowed assistive
-- access" (-25211 / kTCCServicePostEvent denied) - see td-add-and-start-task.applescript's
-- header for the full finding. Using cliclick (CGEvent-based) instead, confirmed working.
property CLICLICK_PATH : "/opt/homebrew/bin/cliclick"

on clickAt(offsetX, offsetY)
	my assertForeground()
	set targetX to round (TD_WIN_X + offsetX)
	set targetY to round (TD_WIN_Y + offsetY)
	do shell script CLICLICK_PATH & " c:" & targetX & "," & targetY
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
