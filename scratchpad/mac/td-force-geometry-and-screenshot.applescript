-- STEP 1 of Mac calibration. Forces the Time Doctor window to a fixed, known
-- size/position (same strategy proven on Windows - see TIMEDOCTOR_UIA_FINDINGS.md)
-- and saves a screenshot of exactly that window, so real pixel offsets for the
-- Add Task field / Add+Start button / Stop button can be measured from it.
--
-- PREREQUISITE: grant Accessibility permission to the app running this script
-- (Terminal, or whatever hosts osascript) in:
--   System Settings -> Privacy & Security -> Accessibility
--
-- USAGE:
--   osascript td-force-geometry-and-screenshot.applescript ~/Desktop/td-mac-screenshot.png

-- Keep these in sync with td-add-and-start-task.applescript and td-stop-current-task.applescript
property TD_WIN_X : 40
property TD_WIN_Y : 40
property TD_WIN_W : 1060
property TD_WIN_H : 880

on run argv
	if (count of argv) is 0 then
		error "Usage: osascript td-force-geometry-and-screenshot.applescript <output-png-path>"
	end if
	set outPath to item 1 of argv

	tell application "System Events"
		if not (exists process "Time Doctor") then
			error "Time Doctor process not found. Is it running?"
		end if
		tell process "Time Doctor"
			set frontmost to true
			if (count of windows) is 0 then
				error "Time Doctor has no open windows. Open the main dashboard window (not just a menu-bar icon) first."
			end if
			set position of window 1 to {TD_WIN_X, TD_WIN_Y}
			set size of window 1 to {TD_WIN_W, TD_WIN_H}
			delay 0.5
			set actualPos to position of window 1
			set actualSize to size of window 1
		end tell
	end tell

	set reportLine to "Actual window geometry after forcing: pos=" & (item 1 of actualPos) & "," & (item 2 of actualPos) & " size=" & (item 1 of actualSize) & "x" & (item 2 of actualSize)
	log reportLine

	set x1 to item 1 of actualPos
	set y1 to item 2 of actualPos
	set w to item 1 of actualSize
	set h to item 2 of actualSize
	set x2 to x1 + w
	set y2 to y1 + h

	-- macOS screencapture: -R x,y,w,h captures a specific screen rectangle.
	do shell script "screencapture -R" & x1 & "," & y1 & "," & w & "," & h & " " & (quoted form of outPath)

	return reportLine & " -- screenshot saved to " & outPath
end run
