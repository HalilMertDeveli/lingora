// The Anthropic client is always a fake here: tests never call the real API.
import assert from "node:assert/strict";
import { beforeEach, test } from "node:test";

import type { ClaudeClient } from "../src/converse.js";
import {
  LEVELS,
  TOPICS,
  WORDS,
  generateDailyReadings,
  planFor,
  systemPrompt,
  validateReading,
} from "../src/daily_reading.js";
import { adminDb, clearFirestore } from "./helpers.js";

const db = adminDb();
const now = new Date("2026-11-19T06:00:00Z");

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

const GLOSS = ["morning", "umbrella", "quiet", "neighbour", "smile"];

/** A valid reading of about [words] words. */
function reading(words = 100) {
  const filler = Array.from({ length: words - GLOSS.length }, (_, i) => (i % 7 === 6 ? "day." : "the"));
  return {
    title: "The Umbrella",
    text: `${GLOSS.join(" ")} ${filler.join(" ")}`,
    summary_tr: "Bir şemsiyenin hikâyesi.",
    glossary: GLOSS.map((word) => ({ word, meaning_tr: "anlam", example: `A ${word}.` })),
    questions: [0, 1, 2].map((i) => ({
      question: `Question ${i}?`,
      options: ["a", "b", "c", "d"],
      answer: i,
      explanation_tr: "Çünkü metinde öyle yazıyor.",
    })),
    talk_prompt: "Do you carry an umbrella?",
  };
}

const json = (obj: unknown) => ({ stop_reason: "end_turn", content: [{ type: "text", text: JSON.stringify(obj) }] });

/** Answers with a text of fitting length for the level in the system prompt. */
function levelAware(params: Call) {
  const level = LEVELS.find((l) => String(params.system).includes(`CEFR ${l}`))!;
  const [min, max] = WORDS[level];
  return json(reading(Math.round((min + max) / 2)));
}

beforeEach(clearFirestore);

test("the day picks a topic and alternates stories and news", () => {
  const a = planFor("2026-11-19");
  const b = planFor("2026-11-20");
  assert.ok(TOPICS.includes(a.topic as (typeof TOPICS)[number]));
  assert.notEqual(a.kind, b.kind);
  assert.notEqual(a.topic, b.topic);
  assert.deepEqual(planFor("2026-11-19"), a);
});

test("the prompt asks for original, safe, level-fitting text", () => {
  const p = systemPrompt("B1", "news", "a cat");
  assert.match(p, /CEFR B1/);
  assert.match(p, /original/i);
  assert.match(p, /no real news events/i);
  assert.match(p, /exactly 5/);
  assert.match(p, /exactly 3/);
});

test("validation rejects bad shapes and glossary words missing from the text", () => {
  assert.equal(typeof validateReading(reading(90), "d", "A1", "story"), "object");
  assert.equal(validateReading(null, "d", "A1", "story"), "not_object");
  assert.match(String(validateReading(reading(20), "d", "A1", "story")), /^length/);
  const fewGloss = { ...reading(90), glossary: reading().glossary.slice(0, 4) };
  assert.equal(validateReading(fewGloss, "d", "A1", "story"), "glossary_count");
  const foreign = reading(90);
  foreign.glossary[0].word = "elephant";
  assert.equal(validateReading(foreign, "d", "A1", "story"), "gloss:elephant");
  const badAnswer = reading(90);
  badAnswer.questions[0].answer = 4;
  assert.equal(validateReading(badAnswer, "d", "A1", "story"), "answer");
  const threeOptions = reading(90);
  threeOptions.questions[1].options = ["a", "b", "c"];
  assert.equal(validateReading(threeOptions, "d", "A1", "story"), "question_shape");
});

test("writes one reading per band under daily/{date}/levels", async () => {
  const { client, calls } = fakeClient(levelAware);
  const r = await generateDailyReadings(db, client, now);
  assert.equal(r.date, "2026-11-19");
  assert.deepEqual(r.written, [...LEVELS]);
  assert.equal(calls.length, 5);
  for (const c of calls) assert.equal(c.model, "claude-sonnet-5-5");
  const b1 = (await db.doc("daily/2026-11-19/levels/B1").get()).data()!;
  assert.equal(b1.level, "B1");
  assert.equal(b1.glossary.length, 5);
  assert.equal(b1.questions.length, 3);
  assert.equal(b1.date, "2026-11-19");
  const day = (await db.doc("daily/2026-11-19").get()).data()!;
  assert.deepEqual(day.levels, [...LEVELS]);
});

test("a re-run only fills the missing bands", async () => {
  // First run: B2 comes back invalid twice and is skipped.
  const first = fakeClient((p) => (String(p.system).includes("CEFR B2") ? json({ title: "x" }) : levelAware(p)));
  const r1 = await generateDailyReadings(db, first.client, now);
  assert.deepEqual(r1.failed, ["B2"]);
  assert.equal(first.calls.length, 6); // one retry for B2
  const second = fakeClient(levelAware);
  const r2 = await generateDailyReadings(db, second.client, now);
  assert.deepEqual(r2.written, ["B2"]);
  assert.equal(second.calls.length, 1);
  assert.deepEqual((await db.doc("daily/2026-11-19").get()).get("levels"), [...LEVELS]);
});

test("refusals and API errors leave the band out instead of crashing", async () => {
  let n = 0;
  const { client } = fakeClient((p) => {
    n++;
    if (String(p.system).includes("CEFR A1")) return { stop_reason: "refusal", content: [] };
    if (String(p.system).includes("CEFR A2")) throw new Error("boom");
    return levelAware(p);
  });
  const r = await generateDailyReadings(db, client, now);
  assert.deepEqual(r.failed, ["A1", "A2"]);
  assert.deepEqual(r.written, ["B1", "B2", "C1"]);
  assert.ok(n >= 5);
});
