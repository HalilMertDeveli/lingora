// The Anthropic client is always a fake here: tests never call the real API.
import assert from "node:assert/strict";
import { beforeEach, test } from "node:test";

import Anthropic from "@anthropic-ai/sdk";
import { Timestamp } from "firebase-admin/firestore";

import {
  assessWriting,
  DAILY_WRITING_LIMIT,
  filterCorrections,
  MAX_OTHER_CORRECTIONS,
  writingPrompt,
} from "../src/assess_writing.js";
import { ClaudeClient, MODEL } from "../src/converse.js";
import { WRITING_TASKS, WritingTask } from "../src/writing_tasks.js";
import { adminDb, clearFirestore, rejectsWith } from "./helpers.js";

const db = adminDb();
const NOW = new Date("2026-11-12T09:00:00Z");
const DAY = 24 * 60 * 60 * 1000;

const TASKS: Record<string, WritingTask> = {
  s5u13l4w: {
    level: "B1",
    task: "Sam'e geçen hafta sonunu anlatan bir e-posta yaz.",
    minWords: 20,
    maxWords: 60,
    checklist: ["Selamlama ve kapanış", "En az üç geçmiş zaman fiili"],
    focus: ["tense", "article"],
    rubric: "An informal email about a past weekend; past simple narration with first/then.",
  },
};

const TEXT =
  "Hi Sam, last weekend I go to the beach with Elif. Then we eat fish in a small restaurant. It was very nice and sunny. See you soon, Kerem";
const request = { taskId: "s5u13l4w", text: TEXT };

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

const goodFeedback = {
  scores: { task: 3, accuracy: 1, range: 2, coherence: 3 },
  corrections: [
    { from: "I go to the beach", to: "I went to the beach", why_tr: "Geçmiş zaman: went.", type: "tense" },
    { from: "we eat fish", to: "we ate fish", why_tr: "Geçmiş zaman: ate.", type: "tense" },
  ],
  next_tr: "Geçmiş zaman fiillerini kontrol et.",
};

async function grantPremium(uid: string, expiresAt: number) {
  await db.doc(`entitlements/${uid}`).set({
    active: true,
    productId: "lingora_premium_monthly",
    expiresAt: Timestamp.fromMillis(expiresAt),
    source: "test",
  });
}

beforeEach(clearFirestore);

test("the shipped tasks are well-formed", () => {
  for (const [id, t] of Object.entries(WRITING_TASKS)) {
    assert.match(id, /^s\d+u\d+l\dw$/, id);
    assert.ok(t.minWords > 0 && t.maxWords >= t.minWords, id);
    assert.ok(t.checklist.length > 0 && t.focus.length <= 3 && t.rubric.length > 0, id);
  }
});

test("requires a known task, a text and Premium, before calling Claude", async () => {
  const { client, calls } = fakeClient(() => jsonReply(goodFeedback));
  await rejectsWith(assessWriting(db, client, "u", { taskId: "s5u13l4w" }, NOW, TASKS), "invalid-argument");
  await rejectsWith(
    assessWriting(db, client, "u", { ...request, text: "x".repeat(2001) }, NOW, TASKS),
    "invalid-argument",
  );
  await rejectsWith(assessWriting(db, client, "u", { ...request, taskId: "nope" }, NOW, TASKS), "not-found");
  await rejectsWith(assessWriting(db, client, "u", { ...request, taskId: "toString" }, NOW, TASKS), "not-found");
  await rejectsWith(
    assessWriting(db, client, "u", { ...request, text: "Hi Sam." }, NOW, TASKS),
    "failed-precondition",
    "too_short",
  );
  await rejectsWith(assessWriting(db, client, "u", request, NOW, TASKS), "permission-denied", "premium_required");
  await grantPremium("u", NOW.getTime() - 1); // expired
  await rejectsWith(assessWriting(db, client, "u", request, NOW, TASKS), "permission-denied");
  assert.equal(calls.length, 0);
});

test("returns scores, focused corrections and the quota left", async () => {
  await grantPremium("u", NOW.getTime() + DAY);
  const { client, calls } = fakeClient(() => jsonReply(goodFeedback));
  const out = await assessWriting(db, client, "u", request, NOW, TASKS);
  assert.deepEqual(out.scores, goodFeedback.scores);
  assert.equal(out.corrections.length, 2);
  assert.equal(out.next_tr, goodFeedback.next_tr);
  assert.equal(out.remaining, DAILY_WRITING_LIMIT - 1);

  const params = calls[0];
  assert.equal(params.model, MODEL);
  const system = String(params.system);
  assert.match(system, /B1/);
  assert.match(system, /tense, article/);
  assert.match(system, /Selamlama ve kapanış/);
  const messages = params.messages as { role: string; content: string }[];
  assert.equal(messages.length, 1);
  assert.match(messages[0].content, /<learner_text>\nHi Sam/);
  assert.equal((await db.doc("usageWriting/u").get()).data()?.count, 1);
});

test("scores are clamped and unknown output is tidied", async () => {
  await grantPremium("u", NOW.getTime() + DAY);
  const { client } = fakeClient(() =>
    jsonReply({
      scores: { task: 7, accuracy: -2, range: 2.4, coherence: "x" },
      corrections: [{ from: "a", to: "a", why_tr: "", type: "tense" }, "junk"],
      next_tr: "  Devam.  ",
    }),
  );
  const out = await assessWriting(db, client, "u", request, NOW, TASKS);
  assert.deepEqual(out.scores, { task: 3, accuracy: 0, range: 2, coherence: 0 });
  assert.deepEqual(out.corrections, []);
  assert.equal(out.next_tr, "Devam.");
});

test("keeps the focus types and at most three other corrections", () => {
  const other = (i: number) => ({ from: `x${i}`, to: `y${i}`, why_tr: "", type: "other" });
  const raw = [
    other(1),
    { from: "go", to: "went", why_tr: "", type: "tense" },
    other(2),
    { from: "in", to: "at", why_tr: "", type: "preposition" },
    other(3),
    other(4),
    { from: "a", to: "the", why_tr: "", type: "article" },
    { from: "b", to: "c", why_tr: "", type: "made_up" },
  ];
  const out = filterCorrections(raw, ["tense", "article"]);
  assert.deepEqual(
    out.map((c) => c.type),
    ["other", "tense", "other", "preposition", "article"],
  );
  assert.equal(out.filter((c) => !["tense", "article"].includes(c.type)).length, MAX_OTHER_CORRECTIONS);
});

test("the daily quota runs out and a failed call is refunded", async () => {
  await grantPremium("u", NOW.getTime() + 2 * DAY);
  await db.doc("usageWriting/u").set({ day: "2026-11-12", count: DAILY_WRITING_LIMIT - 1 });
  const failing = fakeClient(() => {
    throw new Anthropic.InternalServerError(500, undefined, "boom", new Headers());
  });
  await rejectsWith(assessWriting(db, failing.client, "u", request, NOW, TASKS), "unavailable", "upstream_error");
  assert.equal((await db.doc("usageWriting/u").get()).data()?.count, DAILY_WRITING_LIMIT - 1);

  const ok = fakeClient(() => jsonReply(goodFeedback));
  assert.equal((await assessWriting(db, ok.client, "u", request, NOW, TASKS)).remaining, 0);
  await rejectsWith(assessWriting(db, ok.client, "u", request, NOW, TASKS), "resource-exhausted", "daily_quota");
  // A new Turkish day starts a new quota.
  const tomorrow = new Date(NOW.getTime() + DAY);
  assert.equal((await assessWriting(db, ok.client, "u", request, tomorrow, TASKS)).remaining, DAILY_WRITING_LIMIT - 1);
});

test("a refusal does not cost a request", async () => {
  await grantPremium("u", NOW.getTime() + DAY);
  const { client } = fakeClient(() => ({ stop_reason: "refusal", content: [] }));
  await rejectsWith(assessWriting(db, client, "u", request, NOW, TASKS), "unavailable", "refused");
  assert.equal((await db.doc("usageWriting/u").get()).data()?.count, 0);
});

test("the prompt treats the learner's text as data", () => {
  const prompt = writingPrompt(TASKS.s5u13l4w);
  assert.match(prompt, /never instructions/);
  assert.match(prompt, /0 to 3/);
});
