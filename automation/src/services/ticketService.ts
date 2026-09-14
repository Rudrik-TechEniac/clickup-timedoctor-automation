import { clickup, ClickUpTask } from "../clickup/client.js";
import { startTimeDoctorTracking, stopTimeDoctorTracking } from "../timedoctor/index.js";
import { sessionService } from "./sessionService.js";
import { eventLog } from "./sessionService.js";
import { config } from "../config.js";

export class AmbiguousTicketError extends Error {
  constructor(public candidates: ClickUpTask[]) {
    super(`Multiple tickets match - ask the user to pick one.`);
    this.name = "AmbiguousTicketError";
  }
}

export class TicketNotFoundError extends Error {
  constructor(query: string) {
    super(`No ClickUp ticket found matching "${query}".`);
    this.name = "TicketNotFoundError";
  }
}

export class NoActiveTicketError extends Error {
  constructor() {
    super("No ticket is currently active.");
    this.name = "NoActiveTicketError";
  }
}

export class NotConfiguredError extends Error {
  constructor() {
    super(
      "This session isn't configured yet. Before managing tickets, call list_clickup_lists " +
        "to show the user the real ClickUp lists they have tickets in, ask them which one to " +
        "work from, ask what Time Doctor project name to track time under, then call " +
        "configure_workspace with both answers."
    );
    this.name = "NotConfiguredError";
  }
}

/**
 * Per-session workspace config: which ClickUp list to search/manage tickets in, and
 * which Time Doctor project name to file tracked time under. Set once per session via
 * the configure_workspace MCP tool (the user is asked for both, per their instruction -
 * don't assume a list or project). Held in memory for the lifetime of this server
 * process/session - each stdio process or HTTP session is already scoped to one person
 * per the per-user local instance model, so this doesn't need to be persisted to the
 * local state file either.
 */
interface WorkspaceConfig {
  clickupListId: string;
  clickupListName: string;
  timedoctorProject: string;
}

let workspaceConfig: WorkspaceConfig | null = null;

function summarizeTask(t: ClickUpTask) {
  return {
    id: t.id,
    name: t.name,
    url: t.url,
    status: t.status?.status,
    priority: t.priority?.priority ?? null,
    dueDate: t.due_date,
    list: t.list?.name,
  };
}

function requireConfig(): WorkspaceConfig {
  if (!workspaceConfig) throw new NotConfiguredError();
  return workspaceConfig;
}

/** Resolves a free-text query (or exact ClickUp task id) to exactly one task, or throws. */
async function resolveTicket(query: string): Promise<ClickUpTask> {
  const cfg = requireConfig();

  // Exact ClickUp ids resolve directly, regardless of status (open or closed) -
  // bypassing the list search below, which excludes closed tickets by default.
  // Confirmed live: without this, a ticket becomes unreachable by its own id the
  // moment it's marked complete/closed - it couldn't even be moved back out of that
  // status again, since resolveTicket itself couldn't find it any more.
  const trimmed = query.trim();
  if (/^[a-z0-9]{6,12}$/i.test(trimmed)) {
    try {
      return await clickup.getTask(trimmed);
    } catch {
      // Not a real id (or inaccessible) - fall through to free-text search below.
    }
  }

  const matches = await clickup.searchTasksInList(cfg.clickupListId, query);
  if (matches.length === 0) throw new TicketNotFoundError(query);
  if (matches.length === 1) return matches[0];

  // Exact id or exact (case-insensitive) name match disambiguates automatically.
  const exact = matches.find(
    (t) => t.id === query || t.name.toLowerCase() === query.toLowerCase()
  );
  if (exact) return exact;

  throw new AmbiguousTicketError(matches);
}

async function stopActiveSessionIfAny(): Promise<{
  stoppedTask: { id: string; name: string } | null;
  durationSeconds: number | null;
  timedoctorOk: boolean;
}> {
  const active = await sessionService.getActive();
  if (!active) return { stoppedTask: null, durationSeconds: null, timedoctorOk: true };

  const tdResult = await stopTimeDoctorTracking();
  const stopped = await sessionService.stopActive();

  await eventLog.record("ticket_stopped", {
    taskId: active.clickup_task_id,
    durationSeconds: stopped?.duration_seconds,
    timedoctorOk: tdResult.success,
  });

  return {
    stoppedTask: { id: active.clickup_task_id, name: active.task_name },
    durationSeconds: stopped?.duration_seconds ?? null,
    timedoctorOk: tdResult.success,
  };
}

export const ticketService = {
  async listClickupLists() {
    const lists = await clickup.getMyLists();
    return { lists };
  },

  configureWorkspace(clickupListId: string, clickupListName: string, timedoctorProject: string) {
    workspaceConfig = { clickupListId, clickupListName, timedoctorProject };
    return { ...workspaceConfig };
  },

  getWorkspaceConfig() {
    return workspaceConfig ? { ...workspaceConfig } : null;
  },

  async searchTickets(query?: string) {
    const cfg = requireConfig();
    const tasks = await clickup.searchTasksInList(cfg.clickupListId, query);
    return tasks.map(summarizeTask);
  },

  async getTicketDetails(taskId: string) {
    const task = await clickup.getTask(taskId);
    return summarizeTask(task);
  },

  async getCurrentTicket() {
    const active = await sessionService.getActive();
    if (!active) return null;
    const trackedSeconds = await sessionService.totalSecondsForTask(active.clickup_task_id);
    return {
      taskId: active.clickup_task_id,
      taskName: active.task_name,
      taskUrl: active.task_url,
      startedAt: active.started_at,
      trackedSecondsTotal: trackedSeconds,
    };
  },

  async getTrackedTime(taskId: string) {
    const seconds = await sessionService.totalSecondsForTask(taskId);
    return { taskId, trackedSecondsTotal: seconds };
  },

  /** Starts (or switches to) a ticket by free-text query or exact ClickUp task id. */
  async startTicket(query: string) {
    const cfg = requireConfig();
    const task = await resolveTicket(query);

    const { stoppedTask, durationSeconds } = await stopActiveSessionIfAny();

    // Update ClickUp status first; only start the TD timer if that succeeds
    // (section 13: don't start time tracking against a ticket we couldn't validate/update).
    // Resolve against the list's real status strings first - ClickUp workspaces can have
    // whitespace/casing quirks in their actual stored status names (see resolveStatusName).
    const realInProgressStatus = await clickup.resolveStatusName(task.list.id, config.statusInProgress);
    const updated = await clickup.updateTaskStatus(task.id, realInProgressStatus);

    const tdResult = await startTimeDoctorTracking(task.name, task.url, cfg.timedoctorProject);
    await sessionService.start({
      taskId: task.id,
      taskName: task.name,
      taskUrl: task.url,
      timedoctorOk: tdResult.success,
    });

    await eventLog.record("ticket_started", {
      taskId: task.id,
      switchedFrom: stoppedTask,
      timedoctorOk: tdResult.success,
      timedoctorProject: cfg.timedoctorProject,
    });

    return {
      task: summarizeTask(updated),
      switchedFrom: stoppedTask
        ? { ...stoppedTask, durationSeconds }
        : null,
      clickupStatus: realInProgressStatus,
      timedoctorProject: cfg.timedoctorProject,
      timedoctor: tdResult.success
        ? { started: true }
        : { started: false, error: tdResult.error ?? "Unknown Time Doctor automation failure" },
    };
  },

  async stopTicket() {
    const active = await sessionService.getActive();
    if (!active) throw new NoActiveTicketError();

    const tdResult = await stopTimeDoctorTracking();
    const stopped = await sessionService.stopActive();

    // Need the task's list to resolve the real status string (see resolveStatusName) -
    // the session record doesn't carry list id, so fetch the task itself.
    const currentTask = await clickup.getTask(active.clickup_task_id);
    const realInReviewStatus = await clickup.resolveStatusName(currentTask.list.id, config.statusInReview);
    const updated = await clickup.updateTaskStatus(active.clickup_task_id, realInReviewStatus);

    await eventLog.record("ticket_stopped", {
      taskId: active.clickup_task_id,
      durationSeconds: stopped?.duration_seconds,
      timedoctorOk: tdResult.success,
    });

    return {
      task: summarizeTask(updated),
      durationSeconds: stopped?.duration_seconds ?? null,
      clickupStatus: realInReviewStatus,
      timedoctor: tdResult.success
        ? { stopped: true }
        : { stopped: false, error: tdResult.error ?? "Unknown Time Doctor automation failure" },
    };
  },

  /**
   * Sets an arbitrary ClickUp status (e.g. "Complete", "ready for live" - whatever the
   * list actually has) on a specific named ticket, independent of the start/stop time-
   * tracking lifecycle. This is deliberately separate from stopTicket: stopTicket always
   * acts on "whatever is currently active," which is wrong when the user names a specific
   * ticket that may not be the active one (confirmed live: calling stop for a named
   * ticket incorrectly changed a DIFFERENT ticket's status because it happened to be the
   * active one instead).
   * If the named ticket happens to be the one actively tracked AND the new status is a
   * "closed"-type status, also stops time tracking - marking a ticket done implies you're
   * finished working on it.
   */
  async updateTicketStatus(query: string, desiredStatus: string) {
    const task = await resolveTicket(query);
    const statuses = await clickup.getListStatuses(task.list.id);
    const normalize = (s: string) => s.trim().toLowerCase();
    const match = statuses.find((s) => normalize(s.status) === normalize(desiredStatus));
    if (!match) {
      const available = statuses.map((s) => `"${s.status}"`).join(", ");
      throw new TicketNotFoundError(
        `(status "${desiredStatus}" doesn't exist on this ticket's list - available: ${available})`
      );
    }

    const updated = await clickup.updateTaskStatus(task.id, match.status);

    const active = await sessionService.getActive();
    let stoppedTracking: { durationSeconds: number | null; timedoctorOk: boolean } | null = null;
    if (active && active.clickup_task_id === task.id && match.type === "closed") {
      const tdResult = await stopTimeDoctorTracking();
      const stopped = await sessionService.stopActive();
      stoppedTracking = { durationSeconds: stopped?.duration_seconds ?? null, timedoctorOk: tdResult.success };
    }

    await eventLog.record("ticket_status_updated", { taskId: task.id, status: match.status });

    return {
      task: summarizeTask(updated),
      clickupStatus: match.status,
      stoppedTracking,
    };
  },

  /** Lists the real status names/types available on a specific ticket's list. */
  async getAvailableStatuses(query: string) {
    const task = await resolveTicket(query);
    const statuses = await clickup.getListStatuses(task.list.id);
    return { taskId: task.id, taskName: task.name, statuses };
  },

  /** Picks the best next ticket: assigned to the user, open, highest priority, then earliest due date. */
  async startNextTicket() {
    const cfg = requireConfig();
    const tasks = await clickup.searchTasksInList(cfg.clickupListId);
    const inProgress = new Set([config.statusInProgress.toLowerCase()]);
    const candidates = tasks.filter((t) => !inProgress.has(t.status.status.toLowerCase()));

    if (candidates.length === 0) {
      throw new TicketNotFoundError("(no open tickets assigned to you in the configured list)");
    }

    const priorityRank: Record<string, number> = { urgent: 0, high: 1, normal: 2, low: 3 };
    candidates.sort((a, b) => {
      const pa = priorityRank[a.priority?.priority ?? "normal"] ?? 2;
      const pb = priorityRank[b.priority?.priority ?? "normal"] ?? 2;
      if (pa !== pb) return pa - pb;
      const da = a.due_date ? Number(a.due_date) : Infinity;
      const db = b.due_date ? Number(b.due_date) : Infinity;
      return da - db;
    });

    const chosen = candidates[0];
    return this.startTicket(chosen.id);
  },

  /**
   * Builds a "work update" summary: tickets in the configured list that are currently
   * In Progress, On Hold, or Internal Testing AND were last updated on the given day
   * (defaults to today, local time) - i.e. tickets actually touched that day, not
   * everything that happens to be sitting in those statuses indefinitely. Internal
   * Testing is presented as "Completed" in the summary - per the user's instruction,
   * writing this update is itself treated as the completion signal for that status.
   */
  async getWorkUpdate(date?: string) {
    const cfg = requireConfig();
    const targetDate = date ? new Date(date) : new Date();
    if (isNaN(targetDate.getTime())) {
      throw new TicketNotFoundError(`(invalid date "${date}" - use YYYY-MM-DD)`);
    }
    const dayStart = new Date(targetDate.getFullYear(), targetDate.getMonth(), targetDate.getDate());
    const dayEnd = new Date(dayStart.getTime() + 24 * 60 * 60 * 1000);
    const dateLabel = `${dayStart.getFullYear()}-${String(dayStart.getMonth() + 1).padStart(2, "0")}-${String(dayStart.getDate()).padStart(2, "0")}`;

    const tasks = await clickup.searchTasksInList(cfg.clickupListId);

    const normalize = (s: string) => s.trim().toLowerCase();
    const touchedToday = tasks.filter((t) => {
      if (!["in progress", "on hold", "internal testing"].includes(normalize(t.status.status))) {
        return false;
      }
      if (!t.date_updated) return false;
      const updated = new Date(Number(t.date_updated));
      return updated >= dayStart && updated < dayEnd;
    });

    const inProgress = touchedToday.filter((t) => normalize(t.status.status) === "in progress");
    const onHold = touchedToday.filter((t) => normalize(t.status.status) === "on hold");
    const completed = touchedToday.filter((t) => normalize(t.status.status) === "internal testing");

    const STATUS_LABELS: Record<string, string> = {
      "in progress": "In Progress",
      "on hold": "On Hold",
      "internal testing": "Completed",
    };
    const displayStatus = (t: ClickUpTask) => STATUS_LABELS[normalize(t.status.status)] ?? t.status.status;

    const lines = [inProgress, onHold, completed]
      .flat()
      .map((t) => `${t.name} - ${displayStatus(t)}`);

    const message =
      lines.length === 0
        ? `No ticket activity found for ${dateLabel} in the configured list.`
        : `Work update - ${dateLabel}\n\n${lines.join("\n")}`;

    return {
      date: dateLabel,
      inProgress: inProgress.map(summarizeTask),
      onHold: onHold.map(summarizeTask),
      completed: completed.map(summarizeTask),
      message,
    };
  },
};
