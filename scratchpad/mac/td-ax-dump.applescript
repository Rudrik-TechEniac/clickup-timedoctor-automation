-- Dumps the macOS Accessibility (AX) element tree of the running Time Doctor app,
-- looking for a start/stop/pause tracking control.
--
-- PREREQUISITE: grant Accessibility permission to the app running this script
-- (Terminal.app, or Claude Code / osascript's host) in:
--   System Settings -> Privacy & Security -> Accessibility
-- Without this, System Events UI scripting will fail silently or with an error.
--
-- USAGE:
--   osascript td-ax-dump.applescript > td-ax-dump.txt

set maxDepth to 8
set outputLines to {}

on describeElement(el, depth, maxDepth, outputLines)
	if depth > maxDepth then return outputLines
	set indent to ""
	repeat with i from 1 to depth
		set indent to indent & "  "
	end repeat

	set roleStr to "?"
	set nameStr to "?"
	set descStr to "?"
	set actionsStr to "?"

	try
		set roleStr to (role of el as text)
	end try
	try
		set nameStr to (title of el as text)
	end try
	try
		set descStr to (description of el as text)
	end try
	try
		set actionsStr to (actions of el as text)
	end try

	set end of outputLines to indent & "[" & roleStr & "] title='" & nameStr & "' desc='" & descStr & "' actions=" & actionsStr

	try
		set kids to UI elements of el
		repeat with kid in kids
			set outputLines to my describeElement(kid, depth + 1, maxDepth, outputLines)
		end repeat
	end try

	return outputLines
end describeElement

tell application "System Events"
	if not (exists process "Time Doctor") then
		return "ERROR: 'Time Doctor' process not found. Is the app running?"
	end if
	set tdProcess to process "Time Doctor"

	set output to {}
	set end of output to "=== Menu bar items (Time Doctor is likely a menu-bar / status-item app) ==="
	try
		set mbItems to menu bar items of menu bar 1 of tdProcess
		repeat with mb in mbItems
			set output to my describeElement(mb, 1, maxDepth, output)
		end repeat
	on error errMsg
		set end of output to "  (no standard menu bar items, or error: " & errMsg & ")"
	end try

	set end of output to ""
	set end of output to "=== Windows ==="
	try
		set wins to windows of tdProcess
		repeat with w in wins
			set output to my describeElement(w, 1, maxDepth, output)
		end repeat
	on error errMsg
		set end of output to "  (no windows, or error: " & errMsg & ")"
	end try

	set end of output to ""
	set end of output to "=== NOTE: if Time Doctor lives in the macOS menu bar (status item) rather than the Dock, ==="
	set end of output to "=== its control may not appear under 'process \"Time Doctor\"' at all -- in that case it   ==="
	set end of output to "=== is a separate 'menu bar extra' owned by a helper/agent process; list all processes  ==="
	set end of output to "=== with 'tell application \"System Events\" to name of every process' and re-target.    ==="
end tell

set AppleScript's text item delimiters to linefeed
return output as text
