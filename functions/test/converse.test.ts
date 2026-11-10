// The Anthropic client is always a fake here: tests never call the real API.
import assert from "node:assert/strict";
import { beforeEach, test } from "node:test";

import Anthropic from "@anthropic-ai/sdk";
import { Timestamp } from "firebase-admin/firestore";

import { ClaudeClient, converse, DAILY_MESSAGE_LIMIT, MODEL, parseMessages } from "../src/converse.js";
import { adminDb, clearFirestore, rejectsWith } from "./helpers.js";

const db = adminDb();
const NOW = new Date("2026-11-10T09:00:00Z");
const DAY = 24 * 60 * 60 * 1000;

const goodRequest = {
  scenarioId: "cafe",
  messages: [
    { role: "assistant", content: "Hi! What can I get you?" },
    { role: "user", content: "I want coffee." },
  ],
};

type Call = Record<string, unknown>;

function fakeClient(respond: (params: Call) => unknown): { client: ClaudeClient; calls: Call[] } {
  const calls: Call[] = [];
  const client = {
    beta: {
      messages: {
        create: async (params: Call) => {
          calls.push(params);
          return respond(params);
        },
      },
    },
  } as unknown as ClaudeClient;
  return { client, calls };
}

const jsonReply = (obj: unknown) => ({
  stop_reason: "end_turn",
  content: [{ type: "text", text: JSON.stringify(obj) }],
});

async function grantPremium(uid: string, expiresAt: number) {
  await db.doc(`entitlements/${uid}`).set({
    active: true,
    productId: "lingora_premium_monthly",
    expiresAt: Timestamp.fromMillis(expiresAt),
    source: "test",
  });
}

beforeEach(clearFirestore);

test("parseMessages keeps the API's turn rules", () => {
  assert.deepEqual(parseMessages(goodRequest.messages)?.[0], { role: "user", content: "(The scene starts.)" });
  assert.equal(parseMessages([]), null);
  assert.equal(parseMessages([{ role: "user", content: "a" }, { role: "user", content: "b" }]), null);
  assert.equal(parseMessages([{ role: "assistant", content: "hi" }]), null);
  assert.equal(parseMessages([{ role: "system", content: "x" }]), null);
  assert.equal(parseMessages([{ role: "user", content: "x".repeat(1000) }])?.[0].content.length, 400);
});

test("requires an active entitlement", async () => {
  const { client, calls } = fakeClient(() => jsonReply({}));
  await rejectsWith(converse(db, client, "u", goodRequest, NOW), "permission-denied", "premium_required");
  await grantPremium("u", NOW.getTime() - 1); // expired
  await rejectsWith(converse(db, client, "u", goodRequest, NOW), "permission-denied");
  assert.equal(calls.length, 0);
});

test("rejects bad input before calling Claude", async () => {
  await grantPremium("u", NOW.getTime() + DAY);
  const { client, calls } = fakeClient(() => jsonReply({}));
  await rejectsWith(converse(db, client, "u", { ...goodRequest, scenarioId: "nope" }, NOW), "invalid-argument");
  await rejectsWith(converse(db, client, "u", { scenarioId: "cafe", messages: "hi" }, NOW), "invalid-argument");
  assert.equal(calls.length, 0);
});

test("returns the structured reply and sends the expected request", async () => {
  await grantPremium("u", NOW.getTime() + DAY);
  const { client, calls } = fakeClient(() =>
    jsonReply({
      reply: "Sure! Anything to eat?",
      correction: "I would like a coffee, please.",
      tip_tr: "Kibar sipariş",
      done: false,
    }),
  );
  const r = await converse(db, client, "u", goodRequest, NOW);
  assert.deepEqual(r, {
    reply: "Sure! Anything to eat?",
    correction: "I would like a coffee, please.",
    tip_tr: "Kibar sipariş",
    done: false,
    remaining: DAILY_MESSAGE_LIMIT - 1,
  });
  const p = calls[0];
  assert.equal(p.model, MODEL);
  assert.equal(MODEL, "claude-opus-5-5");
  assert.deepEqual(p.betas, ["server-side-fallback-2026-07-01"]);
  assert.equal(p.fallbacks, "default");
  const out = p.output_config as { effort: string; format: { type: string } };
  assert.equal(out.effort, "low");
  assert.equal(out.format.type, "json_schema");
  assert.match(String(p.system), /friendly waiter/);
});

test("a refusal returns the safe in-scene reply", async () => {
  await grantPremium("u", NOW.getTime() + DAY);
  const { client } = fakeClient(() => ({ stop_reason: "refusal", content: [] }));
  const r = await converse(db, client, "u", goodRequest, NOW);
  assert.equal(r.reply, "Let's get back to our scene. What would you like to say?");
  assert.equal(r.correction, "");
  assert.equal(r.done, false);
});

test("enforces the daily quota and refunds failed turns", async () => {
  await grantPremium("u", NOW.getTime() + 7 * DAY);
  const failing = fakeClient(() => {
    throw new Anthropic.APIError(529, undefined, "overloaded", undefined);
  });
  await rejectsWith(converse(db, failing.client, "u", goodRequest, NOW), "unavailable");
  assert.equal((await db.doc("usage/u").get()).get("count"), 0);

  await db.doc("usage/u").set({ day: "2026-11-10", count: DAILY_MESSAGE_LIMIT - 1 });
  const { client, calls } = fakeClient(() => jsonReply({ reply: "ok", correction: "", tip_tr: "", done: true }));
  assert.equal((await converse(db, client, "u", goodRequest, NOW)).remaining, 0);
  await rejectsWith(converse(db, client, "u", goodRequest, NOW), "resource-exhausted", "daily_quota");
  assert.equal(calls.length, 1);
  // A new Turkish day resets the quota.
  const tomorrow = new Date(NOW.getTime() + DAY);
  assert.equal((await converse(db, client, "u", goodRequest, tomorrow)).remaining, DAILY_MESSAGE_LIMIT - 1);
});
