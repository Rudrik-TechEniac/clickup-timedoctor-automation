# ClickUp + Time Doctor Automation (Windows + Mac)

MCP server + backend that lets Claude manage ClickUp tickets and Time Doctor
tracking together: start/stop/switch tickets, auto-pick the next ticket, and
query current/tracked time — all from natural language.

**Windows is proven working** through extensive live testing (see
`../TIMEDOCTOR_UIA_FINDINGS.md`). **Mac has a full parallel implementation
(`scripts/mac/`) but is completely unverified** — written against documentation only,
in a session with no actual Mac access, and its scripts refuse to run
(`CALIBRATED = false`) until someone measures real coordinates on an actual Mac. See
`../TIMEDOCTOR_UIA_FINDINGS.md`'s Mac section and this file's Mac setup below before
relying on it.

## Per-user local instance model

This is **not a shared server that multiple people connect to**. Each person who
wants this runs their **own copy of this `automation/` folder on their own
Windows machine**, with their **own `.env`** containing:
- their own ClickUp Personal API Token (tied to their own ClickUp login — see
  Setup step 1 below),
- their own `CLICKUP_ASSIGNEE_USER_ID` (so ticket search/"next ticket" scopes to
  their own assigned work, not someone else's),
- their own `TD_SCRIPTS_DIR` path, controlling the Time Doctor desktop app
  **already logged into their own Time Doctor account** on that same machine.

Nothing in the code hardcodes a specific person. `.env` is git-ignored and never
committed — it's local, per-machine config, the same way you'd set up any dev
tool locally. If someone else at the company wants this, they clone/copy the
code and follow Setup below on their own machine with their own credentials.

## How it works

- **ClickUp** is controlled via its REST API (personal token) — search tasks, read
  details, update status, add comments.
- **Time Doctor** cannot be controlled via API or accessibility automation at all
  (confirmed — see `../TIMEDOCTOR_UIA_FINDINGS.md`). Control here uses
  **coordinate-based screen automation**: PowerShell scripts in `scripts/windows/`
  force the Time Doctor window to an exact size/position, then click fixed pixel
  offsets to add+start or stop a task. This requires Time Doctor's desktop app to
  be open, logged in, and the machine unlocked.
- **A local JSON file** (`data/state.json`, git-ignored) is the source of truth for
  what's currently active and how much time was tracked — Time Doctor's own state
  is best-effort on top of that, not authoritative. No database server needed.
- **MCP server** (`src/mcp/server.ts`) exposes 8 tools to Claude: `start_ticket`,
  `stop_ticket`, `switch_ticket`, `start_next_ticket`, `get_current_ticket`,
  `search_tickets`, `get_ticket_details`, `get_tracked_time`. Two ways to run it:
  - **stdio** (`npm run mcp:stdio`) — for Claude Desktop/Code on this machine.
  - **HTTP** (`npm run server`, `POST /mcp`) — for a remote Claude connection, and
    this is also where the ClickUp webhook receiver (`POST /webhooks/clickup`) lives.

## Setup

### 1. Get a ClickUp Personal API Token

1. Log into ClickUp in your browser.
2. Click your avatar (bottom-left) → **Settings** → **Apps**.
3. Under **API Token**, click **Generate** (or copy if one already exists).
4. It looks like `pk_12345678_XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX`.

### 2. Find your ClickUp Team (workspace) ID

With the token from step 1:

```bash
curl -H "Authorization: pk_your_token_here" https://api.clickup.com/api/v2/team
```

The response lists your workspace(s); use the `id` field.

### 3. Configure environment

Copy `.env.example` to `.env` and fill in:
- `CLICKUP_API_TOKEN`, `CLICKUP_TEAM_ID` from steps 1-2.
- `CLICKUP_ASSIGNEE_USER_ID` (optional) — restricts ticket search to one user;
  the `/user` endpoint (`GET https://api.clickup.com/api/v2/user` with the same
  Authorization header) returns your own id if left blank isn't precise enough.
- `STATUS_IN_PROGRESS` / `STATUS_IN_REVIEW` / `STATUS_TODO` — must exactly match
  the status names in your ClickUp workspace (case-insensitive), not the app's
  generic defaults if you've customized them.
- `TD_AUTOMATION_DISABLED=true` while testing ClickUp-only flows without wanting
  Time Doctor to actually click anything; set to `false` for real use.

No database setup needed — state (active ticket, session history, event log)
lives in a local JSON file at `data/state.json`, created automatically on first
use.

### 4. Install dependencies

```bash
npm install
```

### 5. Run it

- Local, for Claude Desktop/Code on this machine: `npm run mcp:stdio`
  (add it as an MCP server pointing at this command in your Claude config).
- As an HTTP service (also needed for the ClickUp webhook to have somewhere to
  land — requires this machine or a host to be reachable from the internet,
  e.g. via a tunnel like ngrok/Cloudflare Tunnel for a machine behind NAT):
  `npm run server`.

### 6. (Optional) Register the ClickUp webhook

Once the HTTP server is reachable at a public URL:

```bash
curl -X POST "https://api.clickup.com/api/v2/team/<TEAM_ID>/webhook" \
  -H "Authorization: pk_your_token_here" \
  -H "Content-Type: application/json" \
  -d '{"endpoint": "https://your-public-url/webhooks/clickup", "events": ["taskStatusUpdated", "taskUpdated", "taskAssigneeUpdated"]}'
```

The response includes a `secret` — put it in `CLICKUP_WEBHOOK_SECRET` in `.env`.
Without this set, incoming webhooks are still accepted and logged, just unverified.

## Time Doctor automation caveats (read this before relying on it)

- **Coordinate-based, not name-based.** It clicks fixed pixel positions after
  forcing the window to a known size — see `scripts/windows/td-common.ps1` (Windows)
  or `scripts/mac/*.applescript` (Mac). If Time Doctor updates its UI and moves these
  controls, the calibration needs to be re-measured (take a screenshot, find pixel
  coordinates, update).
- **Requires an unlocked, visible desktop.** It's real mouse/keyboard input —
  it will not work against a locked screen or a remote session that isn't
  actually rendering.
- **Real test data risk.** Every start/stop is a real action in your real Time
  Doctor account. Test with `TD_AUTOMATION_DISABLED=true` first, or expect to
  clean up test task entries afterward.
- **Mac is unverified — do not assume it works.** The scripts exist and follow the
  same proven design as Windows (formula-based sidebar selection, foreground
  re-checked before every click), but were written without any real Mac to test
  against. They refuse to run at all until `CALIBRATED` is manually set to `true` in
  each script, after real measurement — see `../ONBOARDING.md`'s Mac section.
- Full test history and the investigation into why UIA/API control isn't
  possible: `../TIMEDOCTOR_UIA_FINDINGS.md`.

## Platform detection

`src/timedoctor/index.ts` picks the Windows or Mac implementation automatically based
on the OS this server process is actually running on (`os.platform()`) — nothing to
configure. `TD_SCRIPTS_DIR` should point at `scripts/windows` on Windows or
`scripts/mac` on Mac accordingly.

## What's implemented vs. still open (see original spec)

Implemented: ClickUp search/details/status-update, start/stop/switch/next ticket,
Windows Time Doctor start/stop automation (proven live), Mac Time Doctor automation
(written, unverified), local file-based work-session tracking, work-update summaries,
MCP tools (stdio + HTTP), ClickUp webhook receiver (verified + logged).

Not yet implemented: webhook-driven auto-sync (e.g., someone changing a ClickUp
status by hand in the UI reactively stopping/starting the timer — logged today,
not acted on, to avoid feedback loops with our own status updates), verified/working
Mac support (needs real Mac calibration and testing), comment-posting on start/stop,
richer "next ticket" rules beyond priority+due-date.
