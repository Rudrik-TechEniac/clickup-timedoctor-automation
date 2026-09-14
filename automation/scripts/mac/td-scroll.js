// JXA (JavaScript for Automation) scroll-wheel helper.
//
// AppleScript's System Events has NO native "scroll wheel at point" action (confirmed
// via research - System Events supports `click at {x,y}` but nothing equivalent for
// scrolling). This uses the CoreGraphics CGEvent API directly via JXA's ObjC bridge,
// which is the documented, real mechanism for synthesizing a scroll-wheel event:
// https://developer.apple.com/documentation/coregraphics/1541327-cgeventcreatescrollwheelevent
//
// UNTESTED ON REAL HARDWARE - written from documentation only (this was built in a
// Windows-only session with no Mac access). The scroll magnitude/units in particular
// are a real unknown until run for real - see td-common's Windows equivalent
// (Reset-TimeDoctorSidebarScroll) for why this matters: the sidebar's scroll position
// must land at a deterministic point (fully scrolled to the bottom) before the
// formula-based project-row math is valid.
//
// USAGE: osascript -l JavaScript td-scroll.js <x> <y> <deltaY>
//   x, y     - screen coordinates to move the cursor to before scrolling (System
//              Events / most apps scroll whatever is under the cursor, not whatever
//              has keyboard focus).
//   deltaY   - scroll amount; negative scrolls down, positive scrolls up. Windows'
//              equivalent used +/-40 "notches" (40 * WHEEL_DELTA) to guarantee hitting
//              the top/bottom of a short list regardless of starting position - the
//              real per-line unit on macOS is unconfirmed, so this passes deltaY
//              through directly rather than guessing a notch-to-line conversion; the
//              caller should pass a large-magnitude value for the same
//              "guaranteed to hit the boundary" effect until calibrated for real.

ObjC.import('CoreGraphics');

function run(argv) {
  if (argv.length < 3) {
    return JSON.stringify({ success: false, error: "Usage: td-scroll.js <x> <y> <deltaY>" });
  }
  const x = parseFloat(argv[0]);
  const y = parseFloat(argv[1]);
  const deltaY = parseInt(argv[2], 10);

  // Move the cursor first - scroll events on macOS target whatever's under the pointer.
  const moveEvent = $.CGEventCreateMouseEvent(
    null, $.kCGEventMouseMoved, $.CGPointMake(x, y), $.kCGMouseButtonLeft
  );
  $.CGEventPost($.kCGHIDEventTap, moveEvent);
  delay(0.05);

  // kCGScrollEventUnitLine = 1 (line-based scrolling, matching a physical wheel notch
  // more closely than pixel-based scrolling).
  const scrollEvent = $.CGEventCreateScrollWheelEvent(null, 1, 1, deltaY);
  $.CGEventPost($.kCGHIDEventTap, scrollEvent);

  return JSON.stringify({ success: true, x, y, deltaY });
}
