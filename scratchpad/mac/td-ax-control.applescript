-- Attempts to click a Start/Stop/Pause tracking control in the Time Doctor app.
-- This is a TEMPLATE: fill in the exact role/title/path found via td-ax-dump.applescript
-- before relying on it -- guessing blindly at names is likely to fail or click the wrong thing.
--
-- PREREQUISITE: same Accessibility permission requirement as td-ax-dump.applescript.
--
-- USAGE:
--   osascript td-ax-control.applescript start
--   osascript td-ax-control.applescript stop

on run argv
	if (count of argv) is 0 then
		return "Usage: osascript td-ax-control.applescript [start|stop]"
	end if
	set action to item 1 of argv

	tell application "System Events"
		if not (exists process "Time Doctor") then
			return "ERROR: 'Time Doctor' process not found. Is the app running?"
		end if
		set tdProcess to process "Time Doctor"

		-- ATTEMPT 1: menu bar status item -> look for a menu item whose name matches
		-- the action, e.g. "Start Tracking" / "Stop Tracking" / "Pause". Adjust the
		-- match strings below once you know the real labels from td-ax-dump output.
		try
			set mbItems to menu bar items of menu bar 1 of tdProcess
			repeat with mb in mbItems
				click mb
				delay 0.3
				try
					set menuItems to menu items of menu 1 of mb
					repeat with mi in menuItems
						set miTitle to (title of mi as text)
						if action is "start" and (miTitle contains "Start" or miTitle contains "Resume") then
							click mi
							return "Clicked menu item: " & miTitle
						else if action is "stop" and (miTitle contains "Stop" or miTitle contains "Pause") then
							click mi
							return "Clicked menu item: " & miTitle
						end if
					end repeat
				end try
				-- close the menu if nothing matched, so we don't leave it open
				key code 53 -- Escape
			end repeat
		on error errMsg
			-- fall through to attempt 2
		end try

		-- ATTEMPT 2: a window-based button (e.g. an "Activity Bar" widget window),
		-- matched by AXDescription/title containing Start/Stop/Pause/Play.
		try
			set wins to windows of tdProcess
			repeat with w in wins
				set btns to buttons of w
				repeat with b in btns
					set bTitle to ""
					set bDesc to ""
					try
						set bTitle to (title of b as text)
					end try
					try
						set bDesc to (description of b as text)
					end try
					set labelText to bTitle & " " & bDesc
					if action is "start" and (labelText contains "Start" or labelText contains "Play" or labelText contains "Resume") then
						click b
						return "Clicked button: " & labelText
					else if action is "stop" and (labelText contains "Stop" or labelText contains "Pause") then
						click b
						return "Clicked button: " & labelText
					end if
				end repeat
			end repeat
		on error errMsg2
			return "ERROR during window/button search: " & errMsg2
		end try
	end tell

	return "No matching Start/Stop control found. Re-run td-ax-dump.applescript, inspect the real element names, and hard-code the exact path/title here instead of guessing."
end run
