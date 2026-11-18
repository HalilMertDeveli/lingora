// The Anthropic client is always a fake here: tests never call the real API.
import assert from "node:assert/strict";
import { beforeEach, test } from "node:test";

import Anthropic from "@anthropic-ai/sdk";
import { Timestamp } from "firebase-admin/firestore";

import { ClaudeClient, MODEL } from "../src/converse.js";
import {
  analyzeRehearsal,
  cleanAnalysis,
  DAILY_REHEARSAL_LIMIT,
  parseRequest,
  rehearsalPrompt,
  shuffleWords,
} from "../src/rehearsal.js";
import { adminDb, clearFirestore, rejectsWith } from "./helpers.js";

const db = adminDb();
const NOW = new Date("2026-11-10T09:00:00Z");
const DAY = 24 * 60 * 60 * 1000;

const first = {
  rehearsalId: "r_first_1",
  kind: "first",
  items: [
    { question: "Tell me about yourself.", answer: "I am Mert, I am backend developer since three years." },
    {
      question: "Tell me about a project you worked on.",
      answer: "We make a payment app. It was very big project and we use Kotlin. The app send money fast.",
    },
  ],
};

const followUp = {
  rehearsalId: "r_follow_2",
  kind: "interview",
  items: [{ question: "Describe a hard bug you fixed.", answer: "Last year I find a bug in the payment service and I fix it." }],
  previousTags: ["past_simple", "articles", "nonsense"],
  previousGaps: ["contribution"],
};

const goodAnalysis = {
  summary_tr: "Projeyi anlattın ama kendi katkın belirsiz.",
  content_gaps: [
    { type: "contribution", quote: "We make a payment app.", message_tr: "Projenin ne yaptığını anlattın ama senin katkın anlaşılmadı." },
    { type: "unknown", quote: "x", message_tr: "drop me" },
  ],
  grammar_errors: [
    {
      tag: "past_simple",
      explanation_tr: "Geçmiş zamanda aynı hatayı tekrarlıyorsun.",
      examples: [
        { quote: "We make a payment app", fix: "We made a payment app" },
        { quote: "we use Kotlin", fix: "we used Kotlin" },
      ],
    },
    { tag: "articles", explanation_tr: "a/an eksik.", examples: [{ quote: "very big project", fix: "a very big project" }] },
    { tag: "past_simple", explanation_tr: "duplicate", examples: [{ quote: "a", fix: "b" }] },
    { tag: "made_up", explanation_tr: "x", examples: [{ quote: "a", fix: "b" }] },
  ],
  exercises: [
    { kind: "fix_sentence", instruction_tr: "Cümleyi düzelt.", prompt: "We make a payment app.", answer: "We made a payment app.", tag: "past_simple" },
    { kind: "fill_blank", instruction_tr: "Boşluğu doldur.", prompt: "It was ___ very big project.", answer: "a", tag: "articles" },
    { kind: "reorder", instruction_tr: "Sırala.", prompt: "ignored", answer: "We used Kotlin for the app.", tag: "past_simple" },
    { kind: "fill_blank", instruction_tr: "bad: no blank", prompt: "No blank here.", answer: "x", tag: "articles" },
    { kind: "fix_sentence", instruction_tr: "bad: same", prompt: "Same.", answer: "same.", tag: "articles" },
  ],
  retell: { prompt_tr: "Projeyi yeniden anlat.", checklist_tr: ["Kendi katkın", "Sonuç", "Teknoloji"] },
  recurrence: { repeated_tags: ["past_simple"], repeated_gaps: [], note_tr: "should be dropped on first" },
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

async function grantPremium(uid: string, expiresAt: number) {
  await db.doc(`entitlements/${uid}`).set({ active: true, expiresAt: Timestamp.fromMillis(expiresAt), source: "test" });
}

beforeEach(clearFirestore);

test("parseRequest validates ids, kinds, items and keeps only known earlier tags", () => {
  const ok = parseRequest(followUp)!;
  assert.deepEqual(ok.previousTags, ["past_simple", "articles"]);
  assert.deepEqual(ok.previousGaps, ["contribution"]);
  assert.equal(parseRequest({ ...first, rehearsalId: "../x" }), null);
  assert.equal(parseRequest({ ...first, kind: "exam" }), null);
  assert.equal(parseRequest({ ...first, items: [] }), null);
  assert.equal(parseRequest({ ...first, items: [{ question: "q", answer: "x".repeat(4000) }] }), null);
  assert.equal(parseRequest("nope"), null);
});

test("cleanAnalysis keeps only known tags, valid exercises and shuffles reorder words", () => {
  const req = parseRequest(first)!;
  const a = cleanAnalysis(goodAnalysis, req);
  assert.deepEqual(a.content_gaps.map((g) => g.type), ["contribution"]);
  assert.deepEqual(a.grammar_errors.map((e) => e.tag), ["past_simple", "articles"]);
  assert.deepEqual(a.exercises.map((e) => e.kind), ["fix_sentence", "fill_blank", "reorder"]);
  const reorder = a.exercises[2];
  assert.equal(reorder.prompt, "");
  assert.deepEqual([...reorder.words!].sort(), "We used Kotlin for the app.".split(" ").sort());
  assert.notEqual(reorder.words!.join(" "), reorder.answer);
  // A first rehearsal has nothing to recur.
  assert.deepEqual(a.recurrence, { repeated_tags: [], repeated_gaps: [], note_tr: "" });
  assert.equal(a.word_count, 29);
});

test("follow-up recurrence only names earlier tags and gaps", () => {
  const req = parseRequest(followUp)!;
  const a = cleanAnalysis(
    { ...goodAnalysis, recurrence: { repeated_tags: ["past_simple", "passive"], repeated_gaps: ["contribution", "impact"], note_tr: "Geçmiş zaman yine var." } },
    req,
  );
  assert.deepEqual(a.recurrence.repeated_tags, ["past_simple"]);
  assert.deepEqual(a.recurrence.repeated_gaps, ["contribution"]);
  assert.match(rehearsalPrompt(req), /Earlier grammar tags: past_simple, articles/);
});

test("shuffleWords is stable and changes the order", () => {
  const w = ["I", "led", "the", "backend", "team"];
  assert.deepEqual(shuffleWords(w, "s"), shuffleWords(w, "s"));
  assert.notEqual(shuffleWords(w, "s").join(" "), w.join(" "));
});

test("a free user gets exactly one first analysis; it is stored with transcripts", async () => {
  const { client, calls } = fakeClient(() => jsonReply(goodAnalysis));
  const a = await analyzeRehearsal(db, client, "u", first, NOW);
  assert.equal(a.free_left, 0);
  assert.equal(a.grammar_errors[0].tag, "past_simple");
  const p = calls[0];
  assert.equal(p.model, MODEL);
  assert.deepEqual(p.betas, ["server-side-fallback-2026-07-01"]);
  assert.equal(p.fallbacks, "default");
  assert.equal((p.output_config as { format: { type: string } }).format.type, "json_schema");
  assert.match(JSON.stringify(p.messages), /<answer>/);

  const saved = (await db.doc("rehearsals/u/items/r_first_1").get()).data()!;
  assert.equal(saved.kind, "first");
  assert.equal(saved.items[1].answer, first.items[1].answer);
  assert.equal(saved.analysis.exercises.length, 3);

  await rejectsWith(analyzeRehearsal(db, client, "u", { ...first, rehearsalId: "r_first_9" }, NOW), "permission-denied", "premium_required");
  await rejectsWith(analyzeRehearsal(db, client, "u2", followUp, NOW), "permission-denied", "premium_required");
  assert.equal(calls.length, 1);
});

test("too short answers are rejected without using the free try", async () => {
  const { client, calls } = fakeClient(() => jsonReply(goodAnalysis));
  const short = { ...first, items: [{ question: "Tell me about yourself.", answer: "Hi I am" }] };
  await rejectsWith(analyzeRehearsal(db, client, "u", short, NOW), "failed-precondition", "too_short");
  assert.equal(calls.length, 0);
  assert.equal((await analyzeRehearsal(db, client, "u", first, NOW)).free_left, 0);
});

test("a failed call refunds the free try", async () => {
  const failing = fakeClient(() => {
    throw new Anthropic.APIError(529, undefined, "overloaded", undefined);
  });
  await rejectsWith(analyzeRehearsal(db, failing.client, "u", first, NOW), "unavailable");
  assert.equal((await db.doc("usageRehearsal/u").get()).get("freeUsed"), 0);
  const refused = fakeClient(() => ({ stop_reason: "refusal", content: [] }));
  await rejectsWith(analyzeRehearsal(db, refused.client, "u", first, NOW), "unavailable", "refused");
  const { client } = fakeClient(() => jsonReply(goodAnalysis));
  assert.equal((await analyzeRehearsal(db, client, "u", first, NOW)).free_left, 0);
});

test("Premium users get follow-ups with a daily cap", async () => {
  await grantPremium("p", NOW.getTime() + 7 * DAY);
  const { client, calls } = fakeClient(() => jsonReply(goodAnalysis));
  const a = await analyzeRehearsal(db, client, "p", followUp, NOW);
  assert.equal(a.free_left, null);
  assert.match(String(calls[0].system), /This is a follow-up/);
  await db.doc("usageRehearsal/p").set({ day: "2026-11-10", count: DAILY_REHEARSAL_LIMIT }, { merge: true });
  await rejectsWith(analyzeRehearsal(db, client, "p", followUp, NOW), "resource-exhausted", "daily_quota");
  const tomorrow = new Date(NOW.getTime() + DAY);
  assert.equal((await analyzeRehearsal(db, client, "p", followUp, tomorrow)).free_left, null);
});

test("rejects bad input before calling Claude", async () => {
  const { client, calls } = fakeClient(() => jsonReply(goodAnalysis));
  await rejectsWith(analyzeRehearsal(db, client, "u", { kind: "first" }, NOW), "invalid-argument");
  assert.equal(calls.length, 0);
});
