// The Anthropic client is always a fake here: tests never call the real API.
import assert from "node:assert/strict";
import { beforeEach, test } from "node:test";

import Anthropic from "@anthropic-ai/sdk";
import { Timestamp } from "firebase-admin/firestore";

import { ClaudeClient, MODEL } from "../src/converse.js";
import {
  cleanWeakWords,
  conversationReport,
  DAILY_REPORT_LIMIT,
  FREE_DAILY_REPORT_LIMIT,
  MAX_WEAK_WORDS,
  parseTranscript,
} from "../src/conversation_report.js";
import { adminDb, clearFirestore, rejectsWith } from "./helpers.js";

const db = adminDb();
const NOW = new Date("2026-11-10T09:00:00Z");
const DAY = 24 * 60 * 60 * 1000;

const request = {
  scenarioId: "cafe",
  messages: [
    { role: "assistant", content: "Hi! What can I get you?" },
    { role: "user", content: "I want a coffee and three cookie." },
    { role: "assistant", content: "Sure. Anything else?" },
    { role: "user", content: "How much it is?" },
  ],
  pronunciation: [
    { word: "three", heard: "tree", confidence: 0.41 },
    { word: "coffee", heard: "", confidence: 0.62 },
    { word: "Three", heard: "", confidence: 0.9 }, // same word: the weaker evidence wins
    { word: "banana", heard: "", confidence: 0.1 }, // never said: dropped
    { word: "<script>", confidence: 0.1 },
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

const goodReport = {
  mistakes: [
    {
      original: "I want a coffee and three cookie.",
      corrected: "I'd like a coffee and three cookies, please.",
      explanation_tr: "İkiden fazla şey için çoğul -s gerekir.",
    },
    { original: "How much it is?", corrected: "How much is it?", explanation_tr: "Soruda is öne gelir." },
    { original: "Fine sentence.", corrected: "Fine sentence", explanation_tr: "Aynı" }, // not a real fix
  ],
  summary_tr: "Siparişi verdin. Soru cümlelerini çalış.",
};

async function grantPremium(uid: string) {
  await db.doc(`entitlements/${uid}`).set({ active: true, expiresAt: Timestamp.fromMillis(NOW.getTime() + DAY) });
}

beforeEach(clearFirestore);

test("parseTranscript needs at least one learner line", () => {
  assert.equal(parseTranscript([{ role: "assistant", content: "hi" }]), null);
  assert.equal(parseTranscript("x"), null);
  assert.equal(parseTranscript([{ role: "system", content: "x" }]), null);
  assert.equal(parseTranscript(request.messages)?.length, 4);
});

test("cleanWeakWords keeps only said words, weakest first, capped", () => {
  const w = cleanWeakWords(request.pronunciation, "I want a coffee and three cookie.");
  assert.deepEqual(w, [
    { word: "three", heard: "tree", confidence: 0.41 },
    { word: "coffee", heard: "", confidence: 0.62 },
  ]);
  const many = Array.from({ length: 20 }, (_, i) => ({ word: `w${"a".repeat(i + 1)}`, confidence: 0.2 }));
  const said = many.map((m) => m.word).join(" ");
  assert.equal(cleanWeakWords(many, said).length, MAX_WEAK_WORDS);
  assert.deepEqual(cleanWeakWords([{ word: "cafe", confidence: 7 }], "cafe"), [
    { word: "cafe", heard: "", confidence: null },
  ]);
  assert.deepEqual(cleanWeakWords("nope", "x"), []);
});

test("returns Claude's mistakes and the client's pronunciation evidence", async () => {
  await grantPremium("u");
  const { client, calls } = fakeClient(() => jsonReply(goodReport));
  const r = await conversationReport(db, client, "u", request, NOW);
  assert.equal(r.mistakes.length, 2); // the no-op "fix" is dropped
  assert.equal(r.mistakes[1].corrected, "How much is it?");
  assert.equal(r.summary_tr, goodReport.summary_tr);
  assert.deepEqual(
    r.weak_words.map((w) => w.word),
    ["three", "coffee"],
  );
  assert.equal(r.remaining, DAILY_REPORT_LIMIT - 1);

  const p = calls[0];
  assert.equal(p.model, MODEL);
  const out = p.output_config as { format: { type: string } };
  assert.equal(out.format.type, "json_schema");
  assert.match(String(p.system), /Never rate pronunciation/);
  const msgs = p.messages as { role: string; content: string }[];
  assert.equal(msgs.length, 1);
  assert.match(msgs[0].content, /LEARNER: How much it is\?/);
  // The pronunciation evidence is never sent to the model.
  assert.doesNotMatch(JSON.stringify(p), /tree/);
});

test("free users get one report a day; failed calls are refunded", async () => {
  const failing = fakeClient(() => {
    throw new Anthropic.APIError(529, undefined, "overloaded", undefined);
  });
  await rejectsWith(conversationReport(db, failing.client, "u", request, NOW), "unavailable");
  assert.equal((await db.doc("reportUsage/u").get()).get("count"), 0);

  const { client } = fakeClient(() => jsonReply(goodReport));
  assert.equal((await conversationReport(db, client, "u", request, NOW)).remaining, FREE_DAILY_REPORT_LIMIT - 1);
  await rejectsWith(conversationReport(db, client, "u", request, NOW), "resource-exhausted", "report_quota");
});

test("rejects bad input and handles refusals", async () => {
  await grantPremium("u");
  const { client, calls } = fakeClient(() => ({ stop_reason: "refusal", content: [] }));
  await rejectsWith(conversationReport(db, client, "u", { ...request, scenarioId: "x" }, NOW), "invalid-argument");
  await rejectsWith(
    conversationReport(db, client, "u", { scenarioId: "cafe", messages: [{ role: "assistant", content: "hi" }] }, NOW),
    "invalid-argument",
  );
  assert.equal(calls.length, 0);
  const r = await conversationReport(db, client, "u", request, NOW);
  assert.deepEqual(r.mistakes, []);
  assert.equal(r.weak_words.length, 2);
});
