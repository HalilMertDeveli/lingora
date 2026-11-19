// "Günün okuması": once a day, one short original reading per CEFR band
// (A1–C1) with 5 glossed words and 3 questions, shared by every learner.
// Written by the generateDailyReadings schedule (index.ts) to
//   daily/{yyyy-mm-dd}                 { date, levels: [...], kind, topic, createdAt }
//   daily/{yyyy-mm-dd}/levels/{A1..C1} DailyReading
// Signed-in clients may read them (firestore.rules); only this function writes.
//
// Content rules: original fiction or a made-up "news-style" piece. No real
// news events, real people, brands or copied text. Topics come from
// TOPICS below so they stay safe for teenagers too.
import Anthropic from "@anthropic-ai/sdk";
import { FieldValue, Firestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions";

import type { ClaudeClient } from "./converse.js";
import { MODEL } from "./converse.js";
import { dayKey } from "./week.js";

export const LEVELS = ["A1", "A2", "B1", "B2", "C1"] as const;
export type Level = (typeof LEVELS)[number];

/** Target length (words) of the text per band. */
export const WORDS: Record<Level, [number, number]> = {
  A1: [60, 120],
  A2: [90, 160],
  B1: [130, 220],
  B2: [170, 280],
  C1: [210, 340],
};

/** Everyday, school-safe topics; the day picks one (same for all bands). */
export const TOPICS = [
  "a small café that opens on a rainy morning",
  "a neighbourhood football match between two streets",
  "a lost umbrella that travels around a city",
  "a school science fair project about saving water",
  "a grandmother teaching a grandchild to bake bread",
  "a new bicycle lane in a seaside town",
  "a weekend camping trip that goes slightly wrong",
  "a robot vacuum cleaner with a mind of its own",
  "a street cat that visits a library every day",
  "a first day at a new job in an office",
  "a train journey through the mountains in winter",
  "a village that starts a community garden",
  "a teenager learning to play the guitar online",
  "a museum that opens at night for one evening",
  "a family moving to a new city",
  "a power cut during a birthday party",
  "a local market where every stall sells something unusual",
  "a phone left behind in a taxi",
  "a marathon runner who finishes last but happy",
  "a small town that builds a solar-powered bus stop",
  "a cooking competition between two friends",
  "a job interview that starts with an unexpected question",
  "a snow day when schools are closed",
  "a young inventor who makes a quieter alarm clock",
  "an old map found in a second-hand book",
  "a ferry ride and a conversation with a stranger",
  "a team of volunteers cleaning a beach",
  "a holiday photo that shows a surprise in the background",
  "a language exchange meeting in a park",
  "a pet parrot that learns a new word",
  "a rooftop where neighbours watch the stars",
] as const;

export type ReadingKind = "story" | "news";

export interface GlossItem {
  word: string;
  meaning_tr: string;
  example: string;
}

export interface ReadingQuestion {
  question: string;
  options: string[];
  answer: number;
  explanation_tr: string;
}

export interface DailyReading {
  date: string;
  level: Level;
  kind: ReadingKind;
  title: string;
  text: string;
  summary_tr: string;
  glossary: GlossItem[];
  questions: ReadingQuestion[];
  /** One line the voice chat can start from ("Bunu konuşalım"). */
  talk_prompt: string;
}

const SCHEMA = {
  type: "object",
  properties: {
    title: { type: "string" },
    text: { type: "string" },
    summary_tr: { type: "string" },
    glossary: {
      type: "array",
      items: {
        type: "object",
        properties: { word: { type: "string" }, meaning_tr: { type: "string" }, example: { type: "string" } },
        required: ["word", "meaning_tr", "example"],
        additionalProperties: false,
      },
    },
    questions: {
      type: "array",
      items: {
        type: "object",
        properties: {
          question: { type: "string" },
          options: { type: "array", items: { type: "string" } },
          answer: { type: "integer" },
          explanation_tr: { type: "string" },
        },
        required: ["question", "options", "answer", "explanation_tr"],
        additionalProperties: false,
      },
    },
    talk_prompt: { type: "string" },
  },
  required: ["title", "text", "summary_tr", "glossary", "questions", "talk_prompt"],
  additionalProperties: false,
};

/** Day of year (1-366) of a "yyyy-mm-dd" key. */
function dayOfYear(date: string): number {
  const d = new Date(`${date}T00:00:00Z`);
  return Math.floor((d.getTime() - Date.UTC(d.getUTCFullYear(), 0, 1)) / 86_400_000) + 1;
}

/** The day's topic and kind: stories and news-style pieces alternate. */
export function planFor(date: string): { topic: string; kind: ReadingKind } {
  const n = dayOfYear(date);
  return { topic: TOPICS[n % TOPICS.length], kind: n % 2 === 0 ? "story" : "news" };
}

export function systemPrompt(level: Level, kind: ReadingKind, topic: string): string {
  const [min, max] = WORDS[level];
  const form =
    kind === "story"
      ? "a short original story with a clear beginning, middle and end"
      : "a short made-up local news-style article (a light, positive community story)";
  return `You write daily English reading practice for Turkish learners in the Dilmaç app.

Write ${form} at CEFR ${level}, ${min}-${max} words, about: ${topic}.

Rules:
- Completely original. Do not copy or retell any existing book, film, song or article.
- Fictional: no real news events, real people, celebrities, politicians, brands or companies.
- Safe for teenagers: no violence, crime, politics, religion, alcohol, gambling, romance or medical advice.
- Vocabulary and grammar must fit ${level}; short paragraphs separated by blank lines.
- glossary: exactly 5 useful words or short phrases that appear verbatim in the text, each with a short Turkish meaning (meaning_tr) and a new simple English example sentence.
- questions: exactly 3 comprehension questions in English, each with exactly 4 short options, "answer" = index (0-3) of the only correct option, and a one-sentence Turkish explanation (explanation_tr).
- summary_tr: one Turkish sentence summarising the text.
- talk_prompt: one friendly English question (max 15 words) to start a conversation about the text.
- title: max 8 words.`;
}

function wordCount(text: string): number {
  return text.split(/\s+/).filter(Boolean).length;
}

/** Checks a model answer; returns the reading or a reason it was rejected. */
export function validateReading(raw: unknown, date: string, level: Level, kind: ReadingKind): DailyReading | string {
  if (typeof raw !== "object" || raw === null) return "not_object";
  const r = raw as Record<string, unknown>;
  const str = (v: unknown) => (typeof v === "string" ? v.trim() : "");
  const title = str(r.title);
  const text = str(r.text);
  if (!title || title.length > 80) return "title";
  const [min, max] = WORDS[level];
  const words = wordCount(text);
  // Some slack: the model counts loosely.
  if (words < min * 0.7 || words > max * 1.3) return `length:${words}`;
  const lower = text.toLowerCase();
  const glossary = Array.isArray(r.glossary) ? (r.glossary as Record<string, unknown>[]) : [];
  if (glossary.length !== 5) return "glossary_count";
  const gloss: GlossItem[] = [];
  for (const g of glossary) {
    const item = { word: str(g?.word), meaning_tr: str(g?.meaning_tr), example: str(g?.example) };
    if (!item.word || !item.meaning_tr || !lower.includes(item.word.toLowerCase())) return `gloss:${item.word}`;
    gloss.push(item);
  }
  const questions = Array.isArray(r.questions) ? (r.questions as Record<string, unknown>[]) : [];
  if (questions.length !== 3) return "question_count";
  const qs: ReadingQuestion[] = [];
  for (const q of questions) {
    const options = Array.isArray(q?.options) ? (q.options as unknown[]).map(str) : [];
    const answer = q?.answer;
    if (!str(q?.question) || options.length !== 4 || options.some((o) => !o)) return "question_shape";
    if (typeof answer !== "number" || !Number.isInteger(answer) || answer < 0 || answer > 3) return "answer";
    qs.push({ question: str(q.question), options, answer, explanation_tr: str(q.explanation_tr) });
  }
  return {
    date,
    level,
    kind,
    title,
    text,
    summary_tr: str(r.summary_tr),
    glossary: gloss,
    questions: qs,
    talk_prompt: str(r.talk_prompt).slice(0, 120),
  };
}

async function generateOne(
  client: ClaudeClient,
  date: string,
  level: Level,
  kind: ReadingKind,
  topic: string,
): Promise<DailyReading | null> {
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      const response = await client.beta.messages.create({
        model: MODEL,
        max_tokens: 3000,
        betas: ["server-side-fallback-2026-07-01"],
        fallbacks: "default",
        system: systemPrompt(level, kind, topic),
        messages: [{ role: "user", content: `Write the ${level} reading for ${date}.` }],
        output_config: { effort: "low", format: { type: "json_schema", schema: SCHEMA } },
      });
      if (response.stop_reason === "refusal") return null;
      const block = response.content.find((b) => b.type === "text");
      if (!block || block.type !== "text") continue;
      const result = validateReading(JSON.parse(block.text), date, level, kind);
      if (typeof result !== "string") return result;
      logger.warn("daily_reading_rejected", { level, reason: result, attempt });
    } catch (error) {
      if (error instanceof Anthropic.APIError) logger.error(`daily reading ${level}: ${error.status} ${error.message}`);
      else logger.error(`daily reading ${level} failed`, error);
    }
  }
  return null;
}

export interface GenerateResult {
  date: string;
  written: Level[];
  skipped: Level[];
  failed: Level[];
}

/**
 * Writes today's readings (Turkish calendar day of [now]). Levels that
 * already exist are kept, so a re-run only fills gaps.
 */
export async function generateDailyReadings(db: Firestore, client: ClaudeClient, now: Date): Promise<GenerateResult> {
  const date = dayKey(now);
  const { topic, kind } = planFor(date);
  const result: GenerateResult = { date, written: [], skipped: [], failed: [] };
  for (const level of LEVELS) {
    const ref = db.doc(`daily/${date}/levels/${level}`);
    if ((await ref.get()).exists) {
      result.skipped.push(level);
      continue;
    }
    const reading = await generateOne(client, date, level, kind, topic);
    if (!reading) {
      result.failed.push(level);
      continue;
    }
    await ref.set({ ...reading, createdAt: FieldValue.serverTimestamp() });
    result.written.push(level);
  }
  const levels = [...result.skipped, ...result.written].sort();
  await db.doc(`daily/${date}`).set(
    { date, kind, topic, levels, updatedAt: FieldValue.serverTimestamp() },
    { merge: true },
  );
  return result;
}
