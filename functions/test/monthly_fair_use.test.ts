// Per-user monthly AI cost (aiUserSpend) and the Premium fair-use throttle
// (ai_guard.ts): over premiumMonthlyUsd this Turkish month, the daily AI
// limits drop to THROTTLED until the month ends. Claude and TTS are fakes.
import assert from "node:assert/strict";
import { beforeEach, test } from "node:test";

import { Timestamp } from "firebase-admin/firestore";

import {
  meteredClient,
  MONTHLY_FAIR_USE,
  MONTHLY_FAIR_USE_MESSAGE,
  PREMIUM_MONTHLY_USD_CAP,
  premiumThrottled,
  recordSpend,
  resetCaches,
  THROTTLED,
  userSpendThisMonth,
} from "../src/ai_guard.js";
import { assessWriting } from "../src/assess_writing.js";
import { conversationReport, DAILY_REPORT_LIMIT, FREE_DAILY_REPORT_LIMIT } from "../src/conversation_report.js";
import { ClaudeClient, converse, DAILY_MESSAGE_LIMIT, FREE_DAILY_MESSAGE_LIMIT } from "../src/converse.js";
import { DAILY_EXPLAIN_LIMIT, explainMore } from "../src/explain_more.js";
import { analyzeRehearsal, DAILY_REHEARSAL_LIMIT } from "../src/rehearsal.js";
import { FAIR_USE_MINUTES, FAIR_USE_SECONDS, talk } from "../src/talk.js";
import type { TtsClient } from "../src/tts.js";
import { monthKey } from "../src/week.js";
import type { WritingTask } from "../src/writing_tasks.js";
import { adminDb, clearFirestore, rejectsWith } from "./helpers.js";

const db = adminDb();
const NOW = new Date("2026-11-19T09:00:00Z");
const DAY = 24 * 60 * 60 * 1000;
const MONTH = "2026-11";

beforeEach(async () => {
  await clearFirestore();
  resetCaches();
});

async function grantPremium(uid: string) {
  await db.doc(`entitlements/${uid}`).set({ active: true, expiresAt: Timestamp.fromMillis(NOW.getTime() + 60 * DAY) });
}

/** This month's AI cost of [uid] (Turkish month of [at]). */
async function setSpend(uid: string, usd: number, at: Date = NOW) {
  await db.doc(`aiUserSpend/${uid}_${monthKey(at)}`).set({ uid, month: monthKey(at), usd, calls: 1 });
}

type Call = Record<string, unknown>;

/** A fake Claude that answers every call with [obj] as JSON (or streams it for talk). */
function fakeClient(obj: unknown, usage: Record<string, number> = {}): { client: ClaudeClient; calls: Call[] } {
  const calls: Call[] = [];
  const text = JSON.stringify(obj);
  const create = async (params: Call) => {
    calls.push(params);
    if (params.stream) {
      return (async function* () {
        yield { type: "content_block_delta", index: 0, delta: { type: "text_delta", text } };
        yield { type: "message_delta", delta: { stop_reason: "end_turn" } };
      })();
    }
    return { stop_reason: "end_turn", usage, content: [{ type: "text", text }] };
  };
  return { client: { beta: { messages: { create } } } as unknown as ClaudeClient, calls };
}

const silentTts: TtsClient = { synthesize: async () => Buffer.from("mp3") };

/** [p] got past the daily quota: Claude was called (whatever the fake answered). */
async function passesQuota(p: Promise<unknown>, calls: Call[]) {
  await p.catch((e: { code?: string }) => {
    if (e.code === "resource-exhausted") throw e;
  });
  assert.equal(calls.length, 1);
}

const chat = {
  scenarioId: "cafe",
  messages: [
    { role: "assistant", content: "Hi! What can I get you?" },
    { role: "user", content: "I want coffee." },
  ],
};
const chatReply = { reply: "Sure!", correction: "", tip_tr: "", done: false };
const explainReq = {
  question: "She ---- to school every day.",
  options: ["go", "goes", "going", "gone"],
  answer: 1,
  picked: 0,
  explanation: "Geniş zamanda he/she/it ile fiil -s alır.",
  mode: "confused",
};
const TASKS: Record<string, WritingTask> = {
  t1: {
    level: "B1",
    task: "Sam'e geçen hafta sonunu anlatan bir e-posta yaz.",
    minWords: 20,
    maxWords: 60,
    checklist: ["Selamlama ve kapanış"],
    focus: ["tense"],
    rubric: "An informal email about a past weekend.",
  },
};
const writingReq = {
  taskId: "t1",
  text: "Hi Sam, last weekend I go to the beach with Elif. Then we eat fish in a small restaurant. It was very nice and sunny. See you soon, Kerem",
};
const rehearsalReq = {
  rehearsalId: "r_cap_1",
  kind: "interview",
  items: [
    {
      question: "Tell me about a project you worked on.",
      answer: "We make a payment app. It was very big project and we use Kotlin. The app send money fast to many users every day.",
    },
  ],
};

test("defaults: 4 US$ a month, throttled limits below the normal ones, talk fair use 30 minutes", () => {
  assert.equal(PREMIUM_MONTHLY_USD_CAP, 4);
  assert.equal(FAIR_USE_MINUTES, 30);
  assert.deepEqual(THROTTLED, { talkMinutes: 10, messages: 50, explain: 10, writing: 5, report: 3, rehearsal: 2 });
  assert.ok(THROTTLED.talkMinutes < FAIR_USE_MINUTES);
  assert.ok(THROTTLED.messages < DAILY_MESSAGE_LIMIT);
  assert.ok(THROTTLED.explain < DAILY_EXPLAIN_LIMIT);
  assert.ok(THROTTLED.report < DAILY_REPORT_LIMIT);
  assert.ok(THROTTLED.rehearsal < DAILY_REHEARSAL_LIMIT);
});

test("monthKey is the Turkish month", () => {
  assert.equal(monthKey(NOW), MONTH);
  // 30 Nov 21:30 UTC is already 1 December in Istanbul (UTC+3).
  assert.equal(monthKey(new Date("2026-11-30T21:30:00Z")), "2026-12");
  assert.equal(monthKey(new Date("2026-11-30T20:59:00Z")), "2026-11");
});

test("spend is added per uid and month; the metered client records the caller", async () => {
  await recordSpend(db, 0.5, NOW, "a");
  await recordSpend(db, 0.25, NOW, "a");
  await recordSpend(db, 1, NOW, "b");
  await recordSpend(db, 0.1, NOW); // no uid: only the global daily total
  await recordSpend(db, 0, NOW, "a"); // nothing spent: no write
  const a = (await db.doc(`aiUserSpend/a_${MONTH}`).get()).data()!;
  assert.ok(Math.abs(a.usd - 0.75) < 1e-9);
  assert.equal(a.calls, 2);
  assert.equal(a.uid, "a");
  assert.equal(a.month, MONTH);
  assert.ok(a.updatedAt instanceof Timestamp);
  assert.equal(await userSpendThisMonth(db, "b", NOW), 1);
  assert.equal(await userSpendThisMonth(db, "nobody", NOW), 0);
  assert.equal((await db.collection("aiUserSpend").get()).size, 2);

  const { client } = fakeClient({}, { input_tokens: 1_000_000, output_tokens: 100_000 }); // 3 US$
  await meteredClient(client, db, () => NOW, "c").beta.messages.create({ model: "x" } as never);
  assert.ok(Math.abs((await userSpendThisMonth(db, "c", NOW)) - 3) < 1e-9);
  // Next month starts from zero.
  await recordSpend(db, 2, new Date("2026-12-01T09:00:00Z"), "a");
  assert.equal(await userSpendThisMonth(db, "a", new Date("2026-12-01T09:00:00Z")), 2);
  assert.ok(Math.abs((await userSpendThisMonth(db, "a", NOW)) - 0.75) < 1e-9);
});

test("throttled at the cap; the cap comes from config/aiGuard.premiumMonthlyUsd", async () => {
  await setSpend("u", 3.99);
  assert.equal(await premiumThrottled(db, "u", NOW), false);
  await setSpend("u", 4);
  assert.equal(await premiumThrottled(db, "u", NOW), true);
  await db.doc("config/aiGuard").set({ premiumMonthlyUsd: 10 });
  resetCaches();
  assert.equal(await premiumThrottled(db, "u", NOW), false);
});

test("converse: under the cap the normal limit, over it 50 messages then the fair-use error", async () => {
  await grantPremium("u");
  await db.doc("usage/u").set({ day: "2026-11-19", count: THROTTLED.messages });
  await setSpend("u", 3.5);
  const under = fakeClient(chatReply);
  const r = await converse(db, under.client, "u", chat, NOW);
  assert.equal(r.remaining, DAILY_MESSAGE_LIMIT - THROTTLED.messages - 1);

  await setSpend("u", 4.2);
  const over = fakeClient(chatReply);
  await rejectsWith(converse(db, over.client, "u", chat, NOW), "resource-exhausted", MONTHLY_FAIR_USE);
  assert.equal(over.calls.length, 0);

  await db.doc("usage/u").set({ day: "2026-11-19", count: 0 });
  assert.equal((await converse(db, over.client, "u", chat, NOW)).remaining, THROTTLED.messages - 1);
});

test("the fair-use error carries the Turkish message", async () => {
  await grantPremium("u");
  await setSpend("u", 5);
  await db.doc("usage/u").set({ day: "2026-11-19", count: THROTTLED.messages });
  const err = await converse(db, fakeClient(chatReply).client, "u", chat, NOW).catch((e) => e);
  assert.equal(err.code, "resource-exhausted");
  assert.equal(err.message, MONTHLY_FAIR_USE);
  assert.deepEqual(err.details, { message: MONTHLY_FAIR_USE_MESSAGE });
});

test("free users are not affected by the monthly cost", async () => {
  await setSpend("f", 50);
  await db.doc("usage/f").set({ day: "2026-11-19", count: FREE_DAILY_MESSAGE_LIMIT });
  await rejectsWith(converse(db, fakeClient(chatReply).client, "f", chat, NOW), "resource-exhausted", "free_quota");
  await db.doc("reportUsage/f").set({ day: "2026-11-19", count: FREE_DAILY_REPORT_LIMIT });
  await rejectsWith(conversationReport(db, fakeClient({}).client, "f", chat, NOW), "resource-exhausted", "report_quota");
});

test("talk: 30 minutes normally, 10 minutes and 50 messages over the cap", async () => {
  await grantPremium("u");
  const tenMinutes = THROTTLED.talkMinutes * 60;
  await db.doc("voiceUsage/u").set({ day: "2026-11-19", ttsChars: 0, talkSeconds: tenMinutes });
  const under = fakeClient(chatReply);
  const r = await talk(db, under.client, silentTts, "u", chat, NOW, null);
  assert.ok(r.talkSecondsLeft! <= FAIR_USE_SECONDS - tenMinutes && r.talkSecondsLeft! > FAIR_USE_SECONDS - tenMinutes - 60);

  await setSpend("u", 4);
  const over = fakeClient(chatReply);
  await rejectsWith(talk(db, over.client, silentTts, "u", chat, NOW, null), "resource-exhausted", MONTHLY_FAIR_USE);
  assert.equal(over.calls.length, 0);

  // Time left, but the throttled message limit is used up.
  await db.doc("voiceUsage/u").set({ day: "2026-11-19", ttsChars: 0, talkSeconds: 0 });
  await db.doc("usage/u").set({ day: "2026-11-19", count: THROTTLED.messages });
  await rejectsWith(talk(db, over.client, silentTts, "u", chat, NOW, null), "resource-exhausted", MONTHLY_FAIR_USE);
  await db.doc("usage/u").set({ day: "2026-11-19", count: 0 });
  const left = await talk(db, over.client, silentTts, "u", chat, NOW, null);
  assert.ok(left.talkSecondsLeft! <= tenMinutes);
});

test("explain, writing, karne and rehearsal: throttled daily limits over the cap", async () => {
  await grantPremium("u");
  const cases: { name: string; doc: string; limit: number; run: (c: ClaudeClient) => Promise<unknown> }[] = [
    { name: "explain", doc: "explainUsage/u", limit: THROTTLED.explain, run: (c) => explainMore(db, c, "u", explainReq, NOW) },
    { name: "writing", doc: "usageWriting/u", limit: THROTTLED.writing, run: (c) => assessWriting(db, c, "u", writingReq, NOW, TASKS) },
    { name: "report", doc: "reportUsage/u", limit: THROTTLED.report, run: (c) => conversationReport(db, c, "u", chat, NOW) },
    { name: "rehearsal", doc: "usageRehearsal/u", limit: THROTTLED.rehearsal, run: (c) => analyzeRehearsal(db, c, "u", rehearsalReq, NOW) },
  ];
  for (const c of cases) {
    await db.doc(c.doc).set({ day: "2026-11-19", count: c.limit });
    await setSpend("u", 1);
    const under = fakeClient({});
    await passesQuota(c.run(under.client), under.calls).catch((e) => assert.fail(`${c.name} under cap: ${e}`));

    await db.doc(c.doc).set({ day: "2026-11-19", count: c.limit });
    await setSpend("u", PREMIUM_MONTHLY_USD_CAP);
    const over = fakeClient({});
    await rejectsWith(c.run(over.client), "resource-exhausted", MONTHLY_FAIR_USE);
    assert.equal(over.calls.length, 0, c.name);

    await db.doc(c.doc).set({ day: "2026-11-19", count: c.limit - 1 });
    const last = fakeClient({});
    await passesQuota(c.run(last.client), last.calls).catch((e) => assert.fail(`${c.name} last throttled: ${e}`));
  }
});

test("a new month resets the throttle", async () => {
  await grantPremium("u");
  await setSpend("u", 9);
  await db.doc("usage/u").set({ day: "2026-11-30", count: THROTTLED.messages });
  const lastDay = new Date("2026-11-30T12:00:00Z");
  await rejectsWith(converse(db, fakeClient(chatReply).client, "u", chat, lastDay), "resource-exhausted", MONTHLY_FAIR_USE);
  const firstDay = new Date("2026-12-01T09:00:00Z");
  assert.equal(await premiumThrottled(db, "u", firstDay), false);
  await db.doc("usage/u").set({ day: "2026-12-01", count: THROTTLED.messages });
  const r = await converse(db, fakeClient(chatReply).client, "u", chat, firstDay);
  assert.equal(r.remaining, DAILY_MESSAGE_LIMIT - THROTTLED.messages - 1);
});
