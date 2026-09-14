import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { createMcpServer } from "./mcp/server.js";

async function main() {
  const server = createMcpServer();
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error("ClickUp/Time Doctor MCP server running on stdio.");
}

main().catch((err) => {
  console.error("Fatal error starting MCP stdio server:", err);
  process.exit(1);
});
