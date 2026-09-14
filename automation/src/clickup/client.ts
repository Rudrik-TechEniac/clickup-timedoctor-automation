import { config } from "../config.js";

const BASE_URL = "https://api.clickup.com/api/v2";

export interface ClickUpTask {
  id: string;
  name: string;
  text_content?: string;
  description?: string;
  status: { status: string; type: string };
  priority: { priority: string; id: string } | null;
  due_date: string | null;
  date_updated: string | null;
  assignees: { id: number; username: string; email: string }[];
  url: string;
  list: { id: string; name: string };
}

class ClickUpError extends Error {
  constructor(message: string, public status: number, public body: unknown) {
    super(message);
    this.name = "ClickUpError";
  }
}

async function request<T>(
  method: string,
  path: string,
  body?: unknown
): Promise<T> {
  const res = await fetch(`${BASE_URL}${path}`, {
    method,
    headers: {
      Authorization: config.clickupApiToken,
      "Content-Type": "application/json",
    },
    body: body ? JSON.stringify(body) : undefined,
  });

  if (!res.ok) {
    const text = await res.text().catch(() => "");
    throw new ClickUpError(
      `ClickUp API ${method} ${path} failed: ${res.status} ${res.statusText}`,
      res.status,
      text
    );
  }
  if (res.status === 204) return undefined as T;
  return (await res.json()) as T;
}

export interface ClickUpList {
  id: string;
  name: string;
  folderName: string | null;
  spaceName: string | null;
}

export const clickup = {
  async getTask(taskId: string): Promise<ClickUpTask> {
    return request<ClickUpTask>("GET", `/task/${taskId}`);
  },

  /**
   * Distinct ClickUp lists the configured user actually has tasks assigned in,
   * derived from a workspace-wide assignee search rather than enumerating
   * spaces/folders directly. Deliberately NOT using GET /team/{id}/space:
   * ClickUp space membership is separate from workspace membership, and a
   * "member"-role user who hasn't been explicitly added to a Space gets an
   * empty result from that endpoint even though task-assignee search still
   * works fine (assignment doesn't require space membership). This also keeps
   * the list relevant - only lists with real assigned work, not every list in
   * the company.
   *
   * List names alone are often generic (ClickUp defaults many to just "List"),
   * so each distinct list is enriched with its folder name via GET /list/{id}
   * for real disambiguation (e.g. "List" in folder "Persona assistant (pa)").
   */
  async getMyLists(): Promise<ClickUpList[]> {
    const params = new URLSearchParams();
    params.set("include_closed", "false");
    params.set("subtasks", "true");
    if (config.clickupAssigneeUserId) {
      params.append("assignees[]", config.clickupAssigneeUserId);
    }
    const result = await request<{ tasks: ClickUpTask[] }>(
      "GET",
      `/team/${config.clickupTeamId}/task?${params.toString()}`
    );
    const listIds = new Set<string>();
    for (const t of result.tasks) {
      if (t.list?.id) listIds.add(t.list.id);
    }

    const enriched = await Promise.all(
      [...listIds].map(async (id) => {
        try {
          const detail = await request<{
            id: string;
            name: string;
            folder?: { name: string };
            space?: { name: string };
          }>("GET", `/list/${id}`);
          return {
            id: detail.id,
            name: detail.name,
            folderName: detail.folder?.name ?? null,
            spaceName: detail.space?.name ?? null,
          };
        } catch {
          // Fall back to the bare name from the task payload if the list lookup fails.
          const bare = result.tasks.find((t) => t.list?.id === id)?.list;
          return { id, name: bare?.name ?? id, folderName: null, spaceName: null };
        }
      })
    );

    return enriched;
  },

  /** Search tasks assigned to the configured user within one specific ClickUp list. */
  async searchTasksInList(listId: string, query?: string): Promise<ClickUpTask[]> {
    const params = new URLSearchParams();
    params.set("include_closed", "false");
    params.set("subtasks", "true");
    if (config.clickupAssigneeUserId) {
      params.append("assignees[]", config.clickupAssigneeUserId);
    }
    const result = await request<{ tasks: ClickUpTask[] }>(
      "GET",
      `/list/${listId}/task?${params.toString()}`
    );
    let tasks = result.tasks;
    if (query) {
      const q = query.toLowerCase();
      tasks = tasks.filter(
        (t) =>
          t.name.toLowerCase().includes(q) ||
          t.id === query ||
          t.url?.toLowerCase().includes(q)
      );
    }
    return tasks;
  },

  /**
   * List statuses (name + type) as ClickUp actually has them configured for this
   * list - including any accidental whitespace/casing quirks. Real-world workspaces
   * are not guaranteed clean here (found in this project: one list's "in progress"
   * status is literally "in progress " with a trailing space in ClickUp's own data,
   * which the API rejects as an unrecognized status if you send the trimmed form).
   */
  async getListStatuses(listId: string): Promise<{ status: string; type: string }[]> {
    const detail = await request<{ statuses: { status: string; type: string }[] }>(
      "GET",
      `/list/${listId}`
    );
    return detail.statuses;
  },

  /**
   * Resolves a desired status name (from config, which may not exactly match ClickUp's
   * stored string byte-for-byte) to the real status string this list actually has, by
   * comparing case-insensitively with whitespace trimmed. Throws with a helpful message
   * listing real options if nothing matches, rather than letting the API 400 opaquely.
   */
  async resolveStatusName(listId: string, desiredStatus: string): Promise<string> {
    const statuses = await this.getListStatuses(listId);
    const normalize = (s: string) => s.trim().toLowerCase();
    const match = statuses.find((s) => normalize(s.status) === normalize(desiredStatus));
    if (!match) {
      const available = statuses.map((s) => `"${s.status}"`).join(", ");
      throw new ClickUpError(
        `Status "${desiredStatus}" doesn't exist on this list. Available statuses: ${available}`,
        400,
        { availableStatuses: statuses }
      );
    }
    return match.status;
  },

  async updateTaskStatus(taskId: string, status: string): Promise<ClickUpTask> {
    return request<ClickUpTask>("PUT", `/task/${taskId}`, { status });
  },

  async addComment(taskId: string, commentText: string): Promise<unknown> {
    return request("POST", `/task/${taskId}/comment`, {
      comment_text: commentText,
    });
  },

  async getCurrentUser(): Promise<{ user: { id: number; username: string; email: string } }> {
    return request("GET", "/user");
  },

  async registerWebhook(endpointUrl: string, events: string[]): Promise<{ id: string; webhook: { secret: string } }> {
    return request("POST", `/team/${config.clickupTeamId}/webhook`, {
      endpoint: endpointUrl,
      events,
    });
  },
};

export { ClickUpError };
