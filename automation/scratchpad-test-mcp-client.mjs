import { spawn } from "node:child_process";
import readline from "node:readline";

const proc = spawn("npm", ["run", "mcp:stdio", "--silent"], {
  cwd: process.cwd(),
  shell: true,
  stdio: ["pipe", "pipe", "inherit"],
});

const rl = readline.createInterface({ input: proc.stdout });
const pending = new Map();
let nextId = 1;

rl.on("line", (line) => {
  try {
    const msg = JSON.parse(line);
    if (msg.id !== undefined && pending.has(msg.id)) {
      pending.get(msg.id)(msg);
      pending.delete(msg.id);
    }
  } catch {
    // ignore non-JSON lines
  }
});

function send(method, params) {
  return new Promise((resolve) => {
    const id = nextId++;
    pending.set(id, resolve);
    proc.stdin.write(JSON.stringify({ jsonrpc: "2.0", id, method, params }) + "\n");
  });
}

function notify(method, params) {
  proc.stdin.write(JSON.stringify({ jsonrpc: "2.0", method, params }) + "\n");
}

async function callTool(name, args = {}) {
  const res = await send("tools/call", { name, arguments: args });
  return res.result;
}

async function main() {
  await send("initialize", {
    protocolVersion: "2024-11-05",
    capabilities: {},
    clientInfo: { name: "test-harness", version: "0.0.1" },
  });
  notify("notifications/initialized");

  const steps = JSON.parse(process.env.MCP_TEST_STEPS);
  for (const step of steps) {
    const result = await callTool(step.tool, step.args ?? {});
    console.log(`\n=== ${step.tool} ===`);
    console.log(JSON.stringify(result, null, 2));
  }

  proc.stdin.end();
  proc.kill();
  process.exit(0);
}

main();
