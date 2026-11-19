// The Anthropic client is always a fake here: tests never call the real API.
import assert from "node:assert/strict";
import { beforeEach, test } from "node:test";

import Anthropic from "@anthropic-ai/sdk";
import { Timestamp } from "firebase-admin/firestore";

import { ClaudeClient, MODEL } from "../src/converse.js";
import {
  DAILY_EXPLAIN_LIMIT,
  EXPLAIN_SYSTEM,
  explainMore,
  explainPrompt,
  parseExplainRequest,
} from "../src/explain_more.js";
import { adminDb, clearFirestore, rejectsWith } from "./helpers.js";

const db = adminDb();
const NOW = new Date("2026-11-19T09:00:00Z");
const DAY = 24 * 60 * 60 * 1000;

const request = {
  question: "She ---- to school every day.",
  options: ["go", "goes", "going", "gone"],
  answer: 1,
  picked: 0,
  explanation: "Geniş zamanda he/she/it ile fiil -s alır.",
  mode: "confused",
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

const jsonReply = (obj: unknown) => ({ stop_reason: "end_turn", content: [{ type: "text", text: JSON.stringify(obj) }] });

async function grantPremium(uid: string) {
  await db.doc(`entitlements/${uid}`).set({ active: true, expiresAt: Timestamp.fromMillis(NOW.getTime() + DAY) });
}

beforeEach(clearFirestore);

test("parseExplainRequest validates the question and the mode", () => {
  assert.ok(parseExplainRequest(request));
  assert.equal(parseExplainRequest({ ...request, options: ["only"] }), null);
  assert.equal(parseExplainRequest({ ...request, answer: 7 }), null);
  assert.equal(parseExplainRequest({ ...request, mode: "essay" }), null);
  assert.equal(parseExplainRequest({ ...request, mode: "question" }), null); // needs text
  assert.equal(parseExplainRequest({ ...request, question: "  " }), null);
  assert.equal(parseExplainRequest("nope"), null);
  const r = parseExplainRequest({
    ...request,
    picked: 99,
    mode: "question",
    text: "x".repeat(500),
    history: [{ q: "a", a: "b" }, { q: "", a: "dropped" }, 5],
  })!;
  assert.equal(r.picked, null);
  assert.equal(r.text.length, 200);
  assert.deepEqual(r.history, [{ q: "a", a: "b" }]);
});

test("the prompt carries the question, both answers and the follow-up", () => {
  const p = explainPrompt(parseExplainRequest({ ...request, mode: "question", text: "Neden going olmuyor?" })!);
  assert.match(p, /B\) goes/);
  assert.match(p, /Correct answer: B/);
  assert.match(p, /Learner's answer: A/);
  assert.match(p, /<learner_question>Neden going olmuyor\?<\/learner_question>/);
  assert.match(explainPrompt(parseExplainRequest({ ...request, mode: "simpler" })!), /Daha basit anlat/);
  assert.match(EXPLAIN_SYSTEM, /Answer in Turkish, short and simple/);
});

test("Premium gets a short Turkish answer and the quota counts down", async () => {
  await grantPremium("u");
  const { client, calls } = fakeClient(() => jsonReply({ answer_tr: "  She tek kişi, o yüzden goes.  " }));
  const r = await explainMore(db, client, "u", request, NOW);
  assert.equal(r.answer_tr, "She tek kişi, o yüzden goes.");
  assert.equal(r.remaining, DAILY_EXPLAIN_LIMIT - 1);
  const p = calls[0];
  assert.equal(p.model, MODEL);
  assert.equal((p.output_config as { format: { type: string } }).format.type, "json_schema");
  const msgs = p.messages as { role: string; content: string }[];
  assert.match(msgs[0].content, /Anlamadım/);
});

test("free users are refused before any model call", async () => {
  const { client, calls } = fakeClient(() => jsonReply({ answer_tr: "x" }));
  await rejectsWith(explainMore(db, client, "u", request, NOW), "permission-denied", "premium_required");
  assert.equal(calls.length, 0);
  assert.equal((await db.doc("explainUsage/u").get()).exists, false);
});

test("the daily cap holds and failed calls are refunded", async () => {
  await grantPremium("u");
  const failing = fakeClient(() => {
    throw new Anthropic.APIError(529, undefined, "overloaded", undefined);
  });
  await rejectsWith(explainMore(db, failing.client, "u", request, NOW), "unavailable");
  assert.equal((await db.doc("explainUsage/u").get()).get("count"), 0);

  await db.doc("explainUsage/u").set({ day: "2026-11-19", count: DAILY_EXPLAIN_LIMIT - 1 });
  const { client } = fakeClient(() => jsonReply({ answer_tr: "Tamam." }));
  assert.equal((await explainMore(db, client, "u", request, NOW)).remaining, 0);
  await rejectsWith(explainMore(db, client, "u", request, NOW), "resource-exhausted", "explain_quota");
  // A new Turkish day starts again.
  const tomorrow = new Date(NOW.getTime() + DAY);
  await db.doc(`entitlements/u`).set({ active: true, expiresAt: Timestamp.fromMillis(tomorrow.getTime() + DAY) });
  assert.equal((await explainMore(db, client, "u", request, tomorrow)).remaining, DAILY_EXPLAIN_LIMIT - 1);
});

test("bad input, refusals and empty answers", async () => {
  await grantPremium("u");
  const refusing = fakeClient(() => ({ stop_reason: "refusal", content: [] }));
  await rejectsWith(explainMore(db, refusing.client, "u", { ...request, answer: -1 }, NOW), "invalid-argument");
  assert.equal(refusing.calls.length, 0);
  assert.match((await explainMore(db, refusing.client, "u", request, NOW)).answer_tr, /tekrar dene/);

  const empty = fakeClient(() => jsonReply({ answer_tr: "  " }));
  await rejectsWith(explainMore(db, empty.client, "u", request, NOW), "unavailable", "empty_response");
  assert.equal((await db.doc("explainUsage/u").get()).get("count"), 1); // the refusal counted, the empty one was refunded
});
