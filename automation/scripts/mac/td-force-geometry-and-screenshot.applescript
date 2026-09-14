-- STEP 1 of Mac calibration (and a safe general-purpose "just look at the screen"
-- utility afterward). Forces the Time Doctor window to a fixed, known size/position
-- and screenshots exactly that window region - NO clicks, ever, mirroring
-- scripts/windows/td-screenshot-only.ps1's "screenshot only" safety guarantee.
--
-- PREREQUISITE: grant Accessibility permission to whatever actually runs this -
-- empirically the responsible process (Terminal.app, iTerm, or the Node.js binary if
-- invoked via child_process) needs the grant, and which one varies by setup. If this
-- fails silently or with a permissions error, check System Settings -> Privacy &
-- Security -> Accessibility for Terminal/iTerm AND for Node.js itself.
--
-- USAGE: osascript td-force-geometry-and-screenshot.applescript <output-png-path>

property TD_WIN_X : 100
property TD_WIN_Y : 100
property TD_WIN_W : 1060
property TD_WIN_H : 880

on run argv
	if (count of argv) is 0 then
		error "Usage: osascript td-force-geometry-and-screenshot.applescript <output-png-path>"
	end if
	set outPath to item 1 of argv

	tell application "Time Doctor" to activate
	delay 0.3

	tell application "System Events"
		if not (exists process "Time Doctor") then
			error "Time Doctor process not found. Is it running?"
		end if
		tell process "Time Doctor"
			if (count of windows) is 0 then
				error "Time Doctor has no open windows. Open the main dashboard window (not just a menu-bar icon) first."
			end if
			set position of window 1 to {TD_WIN_X, TD_WIN_Y}
			set size of window 1 to {TD_WIN_W, TD_WIN_H}
			delay 0.3
			set actualPos to position of window 1
			set actualSize to size of window 1
		end tell
		set frontApp to name of first application process whose frontmost is true
	end tell

	if frontApp is not "Time Doctor" then
		error "Time Doctor did not come to the foreground (frontmost is currently '" & frontApp & "'). Refusing to proceed - re-run once nothing else has focus."
	end if

	set x1 to item 1 of actualPos
	set y1 to item 2 of actualPos
	set w to item 1 of actualSize
	set h to item 2 of actualSize

	do shell script "screencapture -R" & x1 & "," & y1 & "," & w & "," & h & " " & (quoted form of outPath)

	return "OK: pos=" & x1 & "," & y1 & " size=" & w & "x" & h & " -- screenshot saved to " & outPath
end run
