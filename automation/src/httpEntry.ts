import express from "express";
import { randomUUID } from "node:crypto";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import { createMcpServer } from "./mcp/server.js";
import { webhookRouter } from "./api/webhooks.js";
import { config } from "./config.js";

const app = express();

// Capture raw body (needed for ClickUp webhook HMAC verification) while still parsing JSON.
app.use(
  express.json({
    verify: (req, _res, buf) => {
      (req as unknown as { rawBody: Buffer }).rawBody = buf;
    },
  })
);

app.get("/health", (_req, res) => {
  res.json({ ok: true });
});

app.use("/webhooks", webhookRouter);

// MCP over Streamable HTTP, for remote Claude connections (as opposed to the local
// stdio entrypoint in mcpStdioEntry.ts). A real client session spans multiple HTTP
// requests (initialize -> initialized notification -> tool calls), all carrying the
// same mcp-session-id header, so the transport (and the server bound to it) must be
// kept alive and reused across requests for that id - NOT recreated per request.
const transports = new Map<string, StreamableHTTPServerTransport>();

app.post("/mcp", async (req, res) => {
  try {
    const incomingSessionId = req.header("mcp-session-id");
    let transport = incomingSessionId ? transports.get(incomingSessionId) : undefined;

    if (!transport) {
      const server = createMcpServer();
      transport = new StreamableHTTPServerTransport({
        sessionIdGenerator: () => randomUUID(),
        onsessioninitialized: (sessionId) => {
          transports.set(sessionId, transport!);
        },
      });
      transport.onclose = () => {
        if (transport!.sessionId) transports.delete(transport!.sessionId);
        server.close();
      };
      await server.connect(transport);
    }

    await transport.handleRequest(req, res, req.body);
  } catch (err) {
    console.error("MCP request error:", err);
    if (!res.headersSent) {
      res.status(500).json({ error: "Internal MCP server error" });
    }
  }
});

app.listen(config.port, () => {
  console.log(`ClickUp/Time Doctor automation server listening on port ${config.port}`);
  console.log(`  Health check:    http://localhost:${config.port}/health`);
  console.log(`  ClickUp webhook: http://localhost:${config.port}/webhooks/clickup`);
  console.log(`  MCP (HTTP):      http://localhost:${config.port}/mcp`);
});
