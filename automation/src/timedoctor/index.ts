import os from "node:os";
import * as windowsControl from "./windowsControl.js";
import * as macControl from "./macControl.js";

/**
 * Picks the platform-specific Time Doctor automation at runtime. Windows is proven
 * correct through extensive live testing (see TIMEDOCTOR_UIA_FINDINGS.md and
 * ../../README.md's caveats section). macOS support exists but is UNTESTED - its
 * AppleScript scripts refuse to run until manually calibrated on a real Mac (see
 * scripts/mac/*.applescript and ONBOARDING.md).
 */
const platformImpl = os.platform() === "darwin" ? macControl : windowsControl;

if (os.platform() !== "win32" && os.platform() !== "darwin") {
  throw new Error(
    `Time Doctor automation is only implemented for Windows and macOS (detected: ${os.platform()}).`
  );
}

export const startTimeDoctorTracking = platformImpl.startTimeDoctorTracking;
export const stopTimeDoctorTracking = platformImpl.stopTimeDoctorTracking;
