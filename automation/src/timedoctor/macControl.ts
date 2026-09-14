import { spawn } from "node:child_process";
import path from "node:path";
import { config } from "../config.js";

/**
 * macOS equivalent of windowsControl.ts, shelling out to osascript instead of
 * powershell.exe. UNTESTED - written in a Windows-only session with no Mac access,
 * against documentation only. The AppleScript files themselves refuse to run
 * (CALIBRATED = false) until someone measures real coordinates on an actual Mac -
 * see scripts/mac/*.applescript headers and ../../ONBOARDING.md.
 */

interface ScriptResult {
  success: boolean;
  error?: string;
  [key: string]: unknown;
}

function runAppleScript(scriptName: string, args: string[]): Promise<ScriptResult> {
  return new Promise((resolve, reject) => {
    const scriptPath = path.join(config.tdScriptsDir, scriptName);
    const proc = spawn("osascript", [scriptPath, ...args]);

    let stdout = "";
    let stderr = "";
    proc.stdout.on("data", (d) => (stdout += d.toString()));
    proc.stderr.on("data", (d) => (stderr += d.toString()));

    proc.on("close", (code) => {
      const resultLine = stdout
        .split(/\r?\n/)
        .find((line) => line.startsWith("RESULT_JSON: "));

      if (resultLine) {
        try {
          const parsed = JSON.parse(resultLine.slice("RESULT_JSON: ".length));
          resolve(parsed);
          return;
        } catch {
          // fall through to generic handling below
        }
      }

      if (code === 0) {
        resolve({ success: true, stdout });
      } else {
        // AppleScript's `error` command (used for the CALIBRATED guard, foreground
        // checks, etc.) surfaces here as non-zero exit + message on stderr.
        resolve({
          success: false,
          error: stderr || `Script exited with code ${code}`,
          stdout,
        });
      }
    });

    proc.on("error", (err) => reject(err));
  });
}

export async function startTimeDoctorTracking(
  taskTitle: string,
  ticketLink: string,
  projectName?: string
): Promise<ScriptResult> {
  if (config.tdAutomationDisabled) {
    return { success: true, skipped: true, reason: "TD_AUTOMATION_DISABLED=true" };
  }
  const args = [taskTitle, ticketLink];
  if (projectName) args.push(projectName);
  return runAppleScript("td-add-and-start-task.applescript", args);
}

export async function stopTimeDoctorTracking(): Promise<ScriptResult> {
  if (config.tdAutomationDisabled) {
    return { success: true, skipped: true, reason: "TD_AUTOMATION_DISABLED=true" };
  }
  return runAppleScript("td-stop-current-task.applescript", []);
}
