import dotenv from "dotenv";
import path from "node:path";
import { fileURLToPath } from "node:url";

// Load .env from a fixed path next to this file's project root, NOT process.cwd() -
// when Claude Desktop/Code launches this as an MCP server, its working directory is
// whatever Claude itself was started from, not necessarily this project folder.
const __dirname = path.dirname(fileURLToPath(import.meta.url));
dotenv.config({ path: path.join(__dirname, "..", ".env") });

function required(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

export const config = {
  clickupApiToken: required("CLICKUP_API_TOKEN"),
  clickupTeamId: required("CLICKUP_TEAM_ID"),
  clickupAssigneeUserId: process.env.CLICKUP_ASSIGNEE_USER_ID || undefined,
  clickupWebhookSecret: process.env.CLICKUP_WEBHOOK_SECRET || "",

  port: Number(process.env.PORT || 3000),

  tdScriptsDir: required("TD_SCRIPTS_DIR"),
  tdAutomationDisabled: process.env.TD_AUTOMATION_DISABLED === "true",

  statusInProgress: process.env.STATUS_IN_PROGRESS || "in progress",
  statusInReview: process.env.STATUS_IN_REVIEW || "in review",
  statusTodo: process.env.STATUS_TODO || "to do",
};
