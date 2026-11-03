#!/usr/bin/env bash
# main has signed-in order history; the branch adds a support assistant that lets a model choose a
# refund and then issues it with the shop's payment credentials, with the only limits in the prompt.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p src/routes review-input

cat >src/auth.js <<'JS'
export function requireUser(req, res, next) {
  if (!req.session || !req.session.user) {
    return res.status(401).json({ error: "sign in" });
  }
  req.user = req.session.user;
  next();
}
JS

cat >src/routes/orders.js <<'JS'
import { Router } from "express";
import { requireUser } from "../auth.js";
import { db } from "../db.js";

export const orders = Router();

orders.get("/orders", requireUser, async (req, res) => {
  res.json(await db.orders.forCustomer(req.user.id));
});
JS

git add .
git commit -q -m "feat: order history"

git checkout -q -b feat/support-assistant
cat >src/llm.js <<'JS'
import Anthropic from "@anthropic-ai/sdk";

const client = new Anthropic();

export async function complete({ system, user }) {
  const msg = await client.messages.create({
    model: process.env.SUPPORT_MODEL,
    max_tokens: 512,
    system,
    messages: [{ role: "user", content: user }],
  });
  return msg.content[0].text;
}
JS

cat >src/routes/assistant.js <<'JS'
import { Router } from "express";
import { requireUser } from "../auth.js";
import { db } from "../db.js";
import { complete } from "../llm.js";
import { payments } from "../payments.js";

export const assistant = Router();

const SYSTEM = `You are the shop's support assistant. Reply with JSON only:
{"reply": "<text for the customer>", "refund": null | {"orderId": "<id>", "amountCents": <n>}}
Only refund orders that belong to the customer you are talking to, and never more than the order total.`;

assistant.post("/assistant", requireUser, async (req, res) => {
  const history = await db.orders.forCustomer(req.user.id);
  const text = await complete({
    system: SYSTEM,
    user: `Customer ${req.user.id} orders: ${JSON.stringify(history)}\n\nMessage: ${req.body.message}`,
  });
  const out = JSON.parse(text);
  if (out.refund) {
    await payments.refund(out.refund.orderId, out.refund.amountCents);
  }
  res.json({ reply: out.reply });
});
JS
git add .
git commit -q -m "feat: support assistant that can issue refunds

The assistant reads the customer's orders and can refund one when the
customer asks; the system prompt keeps it to their own orders."

git diff main...HEAD >review-input/change.diff
