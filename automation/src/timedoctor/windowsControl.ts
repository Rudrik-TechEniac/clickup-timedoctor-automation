import { spawn } from "node:child_process";
import path from "node:path";
import { config } from "../config.js";

interface ScriptResult {
  success: boolean;
  error?: string;
  [key: string]: unknown;
}

function runPowerShellScript(
  scriptName: string,
  args: string[]
): Promise<ScriptResult> {
  return new Promise((resolve, reject) => {
    const scriptPath = path.join(config.tdScriptsDir, scriptName);
    const psArgs = [
      "-NoProfile",
      "-ExecutionPolicy",
      "Bypass",
      "-File",
      scriptPath,
      ...args,
    ];

    const proc = spawn("powershell.exe", psArgs, { windowsHide: true });

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

/**
 * Adds "<title>: <link>" as a Time Doctor task and starts it. This is coordinate-based
 * screen automation (Time Doctor's Electron app exposes no accessible UI elements -
 * see TIMEDOCTOR_UIA_FINDINGS.md), so it requires the Time Doctor desktop app to be
 * open, logged in, and visible on screen (not fully occluded doesn't matter, but the
 * machine can't be locked).
 */
export async function startTimeDoctorTracking(
  taskTitle: string,
  ticketLink: string,
  projectName?: string
): Promise<ScriptResult> {
  if (config.tdAutomationDisabled) {
    return { success: true, skipped: true, reason: "TD_AUTOMATION_DISABLED=true" };
  }
  const args = ["-TaskTitle", taskTitle, "-TicketLink", ticketLink];
  if (projectName) {
    args.push("-ProjectName", projectName);
  }
  return runPowerShellScript("td-add-and-start-task.ps1", args);
}

export async function stopTimeDoctorTracking(): Promise<ScriptResult> {
  if (config.tdAutomationDisabled) {
    return { success: true, skipped: true, reason: "TD_AUTOMATION_DISABLED=true" };
  }
  return runPowerShellScript("td-stop-current-task.ps1", []);
}
