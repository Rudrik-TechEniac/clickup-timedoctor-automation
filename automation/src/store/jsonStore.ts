import { readFileSync, writeFileSync, existsSync, mkdirSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

/**
 * Local file-based state store - replaces Postgres. This tool is a single-user,
 * single-process local automation (see README's "per-user local instance" model),
 * so there's no real concurrent-writer scenario to protect against; a plain
 * read-modify-write JSON file is sufficient and avoids requiring a database server
 * to be installed/configured at all.
 */

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const DATA_DIR = path.join(__dirname, "..", "..", "data");
const STORE_FILE = path.join(DATA_DIR, "state.json");

export interface WorkSession {
  id: number;
  clickup_task_id: string;
  task_name: string;
  task_url: string;
  started_at: string;
  stopped_at: string | null;
  duration_seconds: number | null;
  status: "active" | "stopped";
  timedoctor_automation_ok: boolean;
}

export interface EventLogEntry {
  id: number;
  event_type: string;
  detail: Record<string, unknown>;
  created_at: string;
}

interface StoreData {
  sessions: WorkSession[];
  events: EventLogEntry[];
  nextSessionId: number;
  nextEventId: number;
}

function emptyStore(): StoreData {
  return { sessions: [], events: [], nextSessionId: 1, nextEventId: 1 };
}

function load(): StoreData {
  if (!existsSync(STORE_FILE)) return emptyStore();
  try {
    const raw = readFileSync(STORE_FILE, "utf-8");
    return JSON.parse(raw) as StoreData;
  } catch {
    // Corrupt or empty file - don't crash the whole server over it, start fresh.
    return emptyStore();
  }
}

function save(data: StoreData): void {
  if (!existsSync(DATA_DIR)) mkdirSync(DATA_DIR, { recursive: true });
  writeFileSync(STORE_FILE, JSON.stringify(data, null, 2), "utf-8");
}

export const jsonStore = {
  getActiveSession(): WorkSession | null {
    const data = load();
    return data.sessions.find((s) => s.status === "active") ?? null;
  },

  startSession(params: {
    taskId: string;
    taskName: string;
    taskUrl: string;
    timedoctorOk: boolean;
  }): WorkSession {
    const data = load();
    const session: WorkSession = {
      id: data.nextSessionId++,
      clickup_task_id: params.taskId,
      task_name: params.taskName,
      task_url: params.taskUrl,
      started_at: new Date().toISOString(),
      stopped_at: null,
      duration_seconds: null,
      status: "active",
      timedoctor_automation_ok: params.timedoctorOk,
    };
    data.sessions.push(session);
    save(data);
    return session;
  },

  stopActiveSession(): WorkSession | null {
    const data = load();
    const active = data.sessions.find((s) => s.status === "active");
    if (!active) return null;
    const stoppedAt = new Date();
    active.stopped_at = stoppedAt.toISOString();
    active.duration_seconds = Math.floor(
      (stoppedAt.getTime() - new Date(active.started_at).getTime()) / 1000
    );
    active.status = "stopped";
    save(data);
    return active;
  },

  totalSecondsForTask(taskId: string): number {
    const data = load();
    let total = 0;
    for (const s of data.sessions) {
      if (s.clickup_task_id !== taskId) continue;
      if (s.status === "active") {
        total += Math.floor((Date.now() - new Date(s.started_at).getTime()) / 1000);
      } else {
        total += s.duration_seconds ?? 0;
      }
    }
    return total;
  },

  recordEvent(eventType: string, detail: Record<string, unknown>): void {
    const data = load();
    data.events.push({
      id: data.nextEventId++,
      event_type: eventType,
      detail,
      created_at: new Date().toISOString(),
    });
    save(data);
  },
};
