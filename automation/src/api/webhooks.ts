import { Router } from "express";
import crypto from "node:crypto";
import { config } from "../config.js";
import { eventLog } from "../services/sessionService.js";

export const webhookRouter = Router();

function verifySignature(rawBody: Buffer, signatureHeader: string | undefined): boolean {
  if (!config.clickupWebhookSecret) return true; // not configured yet - accept but log unverified below
  if (!signatureHeader) return false;
  const expected = crypto
    .createHmac("sha256", config.clickupWebhookSecret)
    .update(rawBody)
    .digest("hex");
  // timing-safe compare
  const a = Buffer.from(expected);
  const b = Buffer.from(signatureHeader);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

webhookRouter.post("/clickup", async (req, res) => {
  const rawBody: Buffer = (req as unknown as { rawBody: Buffer }).rawBody;
  const signature = req.header("X-Signature");

  const verified = verifySignature(rawBody, signature);
  if (!verified) {
    await eventLog.record("webhook_signature_invalid", { signature });
    res.status(401).json({ error: "Invalid signature" });
    return;
  }
  if (!config.clickupWebhookSecret) {
    await eventLog.record("webhook_received_unverified", {
      note: "CLICKUP_WEBHOOK_SECRET not configured - signature not checked",
    });
  }

  const payload = req.body as { event?: string; task_id?: string; history_items?: unknown };
  await eventLog.record("clickup_webhook", {
    event: payload.event,
    taskId: payload.task_id,
    historyItems: payload.history_items,
  });

  // MVP: log every event for now. Auto-reacting to status changes made outside this
  // system (e.g. someone drags a card in ClickUp's UI) is a follow-up - it needs care
  // to avoid a feedback loop against the status updates start_ticket/stop_ticket already make.
  res.status(200).json({ received: true });
});
