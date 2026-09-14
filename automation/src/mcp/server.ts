import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import {
  ticketService,
  AmbiguousTicketError,
  TicketNotFoundError,
  NoActiveTicketError,
  NotConfiguredError,
} from "../services/ticketService.js";

function errorToText(err: unknown): string {
  if (err instanceof AmbiguousTicketError) {
    const list = err.candidates
      .map((t) => `- ${t.name} (${t.id}) - ${t.url}`)
      .join("\n");
    return `Multiple tickets match. Ask the user which one they mean:\n${list}`;
  }
  if (err instanceof NotConfiguredError) return err.message;
  if (err instanceof TicketNotFoundError) return err.message;
  if (err instanceof NoActiveTicketError) return "No ticket is currently active - nothing to stop.";
  if (err instanceof Error) return `Error: ${err.message}`;
  return `Unknown error: ${String(err)}`;
}

function textResult(obj: unknown) {
  return { content: [{ type: "text" as const, text: JSON.stringify(obj, null, 2) }] };
}

function errorResult(err: unknown) {
  return { content: [{ type: "text" as const, text: errorToText(err) }], isError: true };
}

export function createMcpServer(): McpServer {
  const server = new McpServer(
    {
      name: "clickup-timedoctor-automation",
      version: "0.1.0",
    },
    {
      instructions:
        "This server manages the LOCAL user's own ClickUp tickets and their own Time Doctor desktop app on THIS machine, using their personal ClickUp API token configured in automation/.env - it is NOT the generic claude.ai ClickUp connector (which may be authorized under a different account/person and cannot control Time Doctor at all). " +
        "For any request about starting/stopping/switching tickets, changing a ticket's status (including marking one 'Complete'/done), tracking time, a work/status update, or 'my current ticket', prefer THIS server's tools (start_ticket, stop_ticket, switch_ticket, start_next_ticket, update_ticket_status, get_available_statuses, get_work_update, get_current_ticket, search_tickets, get_ticket_details, get_tracked_time) over a generic ClickUp connector's tools - this one is guaranteed to resolve to the correct person and can actually drive Time Doctor. " +
        "IMPORTANT: stop_ticket only ever acts on whatever is CURRENTLY ACTIVE - if the user names a specific ticket that may not be the active one (e.g. 'mark the CI/CD ticket complete'), use update_ticket_status instead, which targets the named ticket directly. " +
        "Workflow: call list_clickup_lists and configure_workspace once per session before any ticket action (required - other tools will error until this is done).",
    }
  );

  server.registerTool(
    "list_clickup_lists",
    {
      description:
        "List the real ClickUp lists the user currently has tickets assigned in. Call this at the start of a session, before any ticket action, to show the user their actual list names so they can pick one - never guess or assume a list.",
      inputSchema: {},
    },
    async () => {
      try {
        return textResult(await ticketService.listClickupLists());
      } catch (err) {
        return errorResult(err);
      }
    }
  );

  server.registerTool(
    "configure_workspace",
    {
      description:
        "Configure this session: which ClickUp list to manage tickets from, and which Time Doctor project name to file tracked time under. Call list_clickup_lists first, ask the user to pick a list (by name) and name a Time Doctor project, then call this once with their answers. Required before start_ticket/stop_ticket/switch_ticket/start_next_ticket/search_tickets will work.",
      inputSchema: {
        clickupListId: z.string().describe("The ClickUp list id the user picked (from list_clickup_lists)"),
        clickupListName: z.string().describe("The human-readable name of that list, for confirmation messages"),
        timedoctorProject: z
          .string()
          .describe("The Time Doctor project name to type into the 'Type a Project' field when starting tracking"),
      },
    },
    async ({ clickupListId, clickupListName, timedoctorProject }) => {
      try {
        return textResult(ticketService.configureWorkspace(clickupListId, clickupListName, timedoctorProject));
      } catch (err) {
        return errorResult(err);
      }
    }
  );

  server.registerTool(
    "get_workspace_config",
    {
      description: "Get the currently configured ClickUp list and Time Doctor project for this session, if any.",
      inputSchema: {},
    },
    async () => {
      try {
        const cfg = ticketService.getWorkspaceConfig();
        return textResult(cfg ?? { configured: false, message: "Not configured yet - call list_clickup_lists then configure_workspace." });
      } catch (err) {
        return errorResult(err);
      }
    }
  );

  server.registerTool(
    "start_ticket",
    {
      description:
        "[Your personal ClickUp+Time Doctor automation - prefer this over a generic ClickUp connector for ticket work.] Start working on a ClickUp ticket: sets it to In Progress, starts Time Doctor tracking, and stops/switches from whatever ticket was previously active. Accepts a ClickUp task id or a free-text search (name/keyword). Requires configure_workspace to have been called first in this session.",
      inputSchema: { query: z.string().describe("ClickUp task id or free-text ticket name/keyword") },
    },
    async ({ query }) => {
      try {
        return textResult(await ticketService.startTicket(query));
      } catch (err) {
        return errorResult(err);
      }
    }
  );

  server.registerTool(
    "stop_ticket",
    {
      description:
        "[Your personal ClickUp+Time Doctor automation.] Stop the currently active ClickUp ticket: stops Time Doctor tracking, records the work session, and sets the ticket to In Review.",
      inputSchema: {},
    },
    async () => {
      try {
        return textResult(await ticketService.stopTicket());
      } catch (err) {
        return errorResult(err);
      }
    }
  );

  server.registerTool(
    "switch_ticket",
    {
      description:
        "[Your personal ClickUp+Time Doctor automation.] Switch from the current ticket to a different one in one step (stop current, start the requested ticket). Same as start_ticket - starting a new ticket always stops whatever was active.",
      inputSchema: { query: z.string().describe("ClickUp task id or free-text ticket name/keyword to switch to") },
    },
    async ({ query }) => {
      try {
        return textResult(await ticketService.startTicket(query));
      } catch (err) {
        return errorResult(err);
      }
    }
  );

  server.registerTool(
    "start_next_ticket",
    {
      description:
        "[Your personal ClickUp+Time Doctor automation.] Automatically pick the next appropriate ClickUp ticket (assigned to the user, not in progress, highest priority then earliest due date) and start it.",
      inputSchema: {},
    },
    async () => {
      try {
        return textResult(await ticketService.startNextTicket());
      } catch (err) {
        return errorResult(err);
      }
    }
  );

  server.registerTool(
    "update_ticket_status",
    {
      description:
        "[Your personal ClickUp automation - use this instead of a generic ClickUp connector.] Set a specific ClickUp ticket (by id or free-text name) to an arbitrary status - e.g. 'Complete', 'ready for live', or any other status that list actually has. Independent of start/stop time tracking: acts on the NAMED ticket, not whatever happens to be currently active (use this rather than stop_ticket when the user names a specific ticket, since stop_ticket only ever acts on the currently active one). If the named ticket is the one currently being tracked and the new status is a closed/done-type status, this also stops Time Doctor tracking on it. If unsure of the exact status name/spelling, call get_available_statuses first.",
      inputSchema: {
        query: z.string().describe("ClickUp task id or free-text ticket name/keyword"),
        status: z.string().describe("Desired status name (e.g. 'Complete', 'ready for live') - must match one of the list's real statuses"),
      },
    },
    async ({ query, status }) => {
      try {
        return textResult(await ticketService.updateTicketStatus(query, status));
      } catch (err) {
        return errorResult(err);
      }
    }
  );

  server.registerTool(
    "get_available_statuses",
    {
      description:
        "[Your personal ClickUp automation.] List the real status names available on a specific ticket's list (e.g. to find the exact spelling before calling update_ticket_status).",
      inputSchema: { query: z.string().describe("ClickUp task id or free-text ticket name/keyword") },
    },
    async ({ query }) => {
      try {
        return textResult(await ticketService.getAvailableStatuses(query));
      } catch (err) {
        return errorResult(err);
      }
    }
  );

  server.registerTool(
    "get_current_ticket",
    {
      description: "[Your personal ClickUp+Time Doctor automation.] Get the ClickUp ticket currently being tracked, if any, and how long it's been tracked in total.",
      inputSchema: {},
    },
    async () => {
      try {
        const current = await ticketService.getCurrentTicket();
        return textResult(current ?? { active: false, message: "No ticket is currently active." });
      } catch (err) {
        return errorResult(err);
      }
    }
  );

  server.registerTool(
    "search_tickets",
    {
      description: "Search ClickUp tickets assigned to the user by free-text name/keyword. Omit query to list all open tickets.",
      inputSchema: { query: z.string().optional().describe("Free-text search term") },
    },
    async ({ query }) => {
      try {
        return textResult(await ticketService.searchTickets(query));
      } catch (err) {
        return errorResult(err);
      }
    }
  );

  server.registerTool(
    "get_ticket_details",
    {
      description: "Get full details (description, status, priority, due date, assignees, list) for a specific ClickUp task id.",
      inputSchema: { taskId: z.string().describe("ClickUp task id") },
    },
    async ({ taskId }) => {
      try {
        return textResult(await ticketService.getTicketDetails(taskId));
      } catch (err) {
        return errorResult(err);
      }
    }
  );

  server.registerTool(
    "get_tracked_time",
    {
      description: "Get total tracked time (across all sessions) for a specific ClickUp task id.",
      inputSchema: { taskId: z.string().describe("ClickUp task id") },
    },
    async ({ taskId }) => {
      try {
        return textResult(await ticketService.getTrackedTime(taskId));
      } catch (err) {
        return errorResult(err);
      }
    }
  );

  server.registerTool(
    "get_work_update",
    {
      description:
        "[Your personal ClickUp automation.] Build a work update summary for the user: tickets in the configured list that were touched (updated) on a given day (defaults to today) and are currently In Progress, On Hold, or Internal Testing. Internal Testing tickets are presented as 'Completed' in the summary - use this whenever the user asks for a work update, status update, EOD summary, or 'what did I work on today'. Returns both a ready-to-send text message and the raw grouped ticket lists.",
      inputSchema: {
        date: z
          .string()
          .optional()
          .describe("Date to summarize, YYYY-MM-DD. Defaults to today if omitted."),
      },
    },
    async ({ date }) => {
      try {
        return textResult(await ticketService.getWorkUpdate(date));
      } catch (err) {
        return errorResult(err);
      }
    }
  );

  return server;
}
