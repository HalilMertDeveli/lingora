// End-of-conversation "karne" for the voice coach (Sesli Konuşma Koçu).
// The app sends { scenarioId, messages: [{ role, content }], pronunciation:
// [{ word, heard?, confidence? }] } and gets back { mistakes: [{ original,
// corrected, explanation_tr }], summary_tr, weak_words: [{ word, heard,
// confidence }], remaining }. Voice chats may also send { mode: "free" | characterId,
// topic, level, goal } instead of scenarioId, and the in-flow corrections
// { corrections: [{ original, corrected, tip_tr }] } (talk.ts recasts).
//
// Grammar feedback comes from Claude. Pronunciation does NOT: weak_words is
// only the on-device speech-recognition evidence the app sent (low
// confidence, the recognizer hesitating between guesses, or the learner
// fixing a misheard word), cleaned and capped here. No scores are invented.
import Anthropic from "@anthropic-ai/sdk";
import { FieldValue, Firestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { HttpsError } from "firebase-functions/v2/https";

import { ClaudeClient, hasPremium, MAX_CHARS, MODEL } from "./converse.js";
import { ScenarioPrompt } from "./scenarios.js";
import { reportScene, resolveContext } from "./talk_context.js";
import { dayKey } from "./week.js";

export const REPORT_MAX_MESSAGES = 40;
export const MAX_MISTAKES = 8;
export const MAX_WEAK_WORDS = 8;
/** Reports per Turkish day: Premium, and the free taste. */
export const DAILY_REPORT_LIMIT = 10;
export const FREE_DAILY_REPORT_LIMIT = 1;

const REPORT_SCHEMA = {
  type: "object",
  properties: {
    mistakes: {
      type: "array",
      items: {
        type: "object",
        properties: {
          original: { type: "string" },
          corrected: { type: "string" },
          explanation_tr: { type: "string" },
        },
        required: ["original", "corrected", "explanation_tr"],
        additionalProperties: false,
      },
    },
    summary_tr: { type: "string" },
  },
  required: ["mistakes", "summary_tr"],
  additionalProperties: false,
};

export interface Mistake {
  original: string;
  corrected: string;
  explanation_tr: string;
}

export interface WeakWord {
  word: string;
  /** What the recognizer wrote instead, or "" when it only was unsure. */
  heard: string;
  /** Recognizer confidence 0..1 for the phrase, or null when it gave none. */
  confidence: number | null;
}

export interface ConversationReport {
  mistakes: Mistake[];
  summary_tr: string;
  weak_words: WeakWord[];
  remaining: number;
}

type Line = { role: "user" | "assistant"; content: string };

/** The transcript, any order of turns; at least one learner line. */
export function parseTranscript(raw: unknown): Line[] | null {
  if (!Array.isArray(raw)) return null;
  const out: Line[] = [];
  for (const m of raw.slice(-REPORT_MAX_MESSAGES)) {
    if (typeof m !== "object" || m === null) return null;
    const { role, content } = m as Record<string, unknown>;
    if ((role !== "user" && role !== "assistant") || typeof content !== "string") return null;
    const text = content.trim().slice(0, MAX_CHARS);
    if (text) out.push({ role, content: text });
  }
  return out.some((l) => l.role === "user") ? out : null;
}

const WORD = /^[a-z][a-z'-]{0,29}$/;

function wordsOf(text: string): Set<string> {
  return new Set(text.toLowerCase().match(/[a-z][a-z'-]*/g) ?? []);
}

/**
 * Keeps only evidence about words the learner actually said (in the sent
 * transcript), one entry per word (the least confident), least confident first.
 */
export function cleanWeakWords(raw: unknown, learnerText: string): WeakWord[] {
  if (!Array.isArray(raw)) return [];
  const said = wordsOf(learnerText);
  const byWord = new Map<string, WeakWord>();
  for (const e of raw.slice(0, 60)) {
    if (typeof e !== "object" || e === null) continue;
    const r = e as Record<string, unknown>;
    const word = typeof r.word === "string" ? r.word.trim().toLowerCase() : "";
    if (!WORD.test(word) || !said.has(word)) continue;
    const heard =
      typeof r.heard === "string" ? r.heard.toLowerCase().replace(/[^a-z' -]/g, "").trim().slice(0, 40) : "";
    const c = typeof r.confidence === "number" && Number.isFinite(r.confidence) ? r.confidence : null;
    const confidence = c === null || c < 0 || c > 1 ? null : Math.round(c * 100) / 100;
    const entry: WeakWord = { word, heard: heard === word ? "" : heard, confidence };
    const old = byWord.get(word);
    if (!old || rank(entry) < rank(old)) byWord.set(word, entry);
  }
  return [...byWord.values()].sort((a, b) => rank(a) - rank(b)).slice(0, MAX_WEAK_WORDS);
}

/** Misheard words first, then by confidence (unknown counts as 0.5). */
function rank(w: WeakWord): number {
  return (w.heard ? 0 : 1) + (w.confidence ?? 0.5);
}

export function reportPrompt(s: ScenarioPrompt): string {
  return `You are an English teacher for Turkish speakers, reviewing a finished speaking practice role-play.

Scene: ${s.setting}
The app played: ${s.partner}.
Learner's goal: ${s.goal}
Learner level: ${s.level} (CEFR).

The learner's lines are marked LEARNER. They were often spoken and turned into text by speech recognition, so ignore punctuation, capitalization and obvious recognition slips (a single odd word that a listener would understand from context).

Return:
- "mistakes": up to ${MAX_MISTAKES} of the learner's sentences that contain a real grammar or word-choice mistake a native speaker would notice. "original" is the learner's sentence exactly as written, "corrected" a natural corrected version of the whole sentence, "explanation_tr" one short sentence in Turkish explaining the mistake, ideally naming the Turkish habit behind it (missing article, "I am agree", missing third-person -s, wrong tense). Most important mistakes first. Never list a sentence that is already fine. An empty list is a good result.
- "summary_tr": two short, encouraging sentences in Turkish: what went well and the one thing to practise next.

Never rate pronunciation: you only see text.`;
}

function transcriptText(lines: Line[]): string {
  return lines.map((l) => `${l.role === "user" ? "LEARNER" : "PARTNER"}: ${l.content}`).join("\n");
}

async function takeReportQuota(db: Firestore, uid: string, now: Date, limit: number): Promise<number> {
  const ref = db.doc(`reportUsage/${uid}`);
  const day = dayKey(now);
  return db.runTransaction(async (tx) => {
    const u = (await tx.get(ref)).data();
    const used = u?.day === day ? ((u.count as number) ?? 0) : 0;
    if (used >= limit) throw new HttpsError("resource-exhausted", "report_quota");
    tx.set(ref, { day, count: used + 1 });
    return limit - used - 1;
  });
}

async function refundReportQuota(db: Firestore, uid: string, now: Date): Promise<void> {
  const ref = db.doc(`reportUsage/${uid}`);
  await db.runTransaction(async (tx) => {
    const u = (await tx.get(ref)).data();
    if (u?.day === dayKey(now) && (u.count as number) > 0) tx.update(ref, { count: FieldValue.increment(-1) });
  });
}

const clean = (v: unknown, max: number) => (typeof v === "string" ? v.trim().slice(0, max) : "");
const same = (a: string, b: string) =>
  a.toLowerCase().replace(/[^a-z0-9]/g, "") === b.toLowerCase().replace(/[^a-z0-9]/g, "");

/**
 * Corrections collected silently during a voice chat ({ original, corrected,
 * tip_tr }), kept only for sentences the learner really said.
 */
export function cleanCorrections(raw: unknown, lines: Line[]): Mistake[] {
  if (!Array.isArray(raw)) return [];
  const said = lines.filter((l) => l.role === "user").map((l) => l.content);
  const out: Mistake[] = [];
  for (const e of raw.slice(0, 40)) {
    if (typeof e !== "object" || e === null) continue;
    const r = e as Record<string, unknown>;
    const original = clean(r.original, MAX_CHARS);
    const corrected = clean(r.corrected, MAX_CHARS);
    if (!original || !corrected || same(original, corrected)) continue;
    if (!said.some((t) => same(t, original))) continue;
    if (out.some((m) => same(m.original, original))) continue;
    out.push({ original, corrected, explanation_tr: clean(r.tip_tr, 300) });
    if (out.length >= MAX_MISTAKES) break;
  }
  return out;
}

export async function conversationReport(
  db: Firestore,
  client: ClaudeClient,
  uid: string,
  data: unknown,
  now: Date,
): Promise<ConversationReport> {
  const body = (typeof data === "object" && data !== null ? data : {}) as Record<string, unknown>;
  // A role-play scenario, free talk or a character (talk_context.ts).
  const ctx = resolveContext(body);
  const scenario = ctx ? reportScene(ctx) : null;
  const lines = parseTranscript(body.messages);
  if (!scenario || !lines) throw new HttpsError("invalid-argument", "invalid_request");

  const learnerText = lines.filter((l) => l.role === "user").map((l) => l.content).join("\n");
  const weak_words = cleanWeakWords(body.pronunciation, learnerText);
  const inFlow = cleanCorrections(body.corrections, lines);
  const premium = await hasPremium(db, uid, now);
  const remaining = await takeReportQuota(db, uid, now, premium ? DAILY_REPORT_LIMIT : FREE_DAILY_REPORT_LIMIT);

  try {
    const response = await client.beta.messages.create({
      model: MODEL,
      max_tokens: 3000,
      betas: ["server-side-fallback-2026-07-01"],
      fallbacks: "default",
      system: reportPrompt(scenario),
      messages: [{ role: "user", content: transcriptText(lines) }],
      output_config: {
        effort: "low",
        format: { type: "json_schema", schema: REPORT_SCHEMA },
      },
    });

    if (response.stop_reason === "refusal") {
      return { mistakes: inFlow, summary_tr: "Bu sohbet için karne hazırlanamadı.", weak_words, remaining };
    }
    const text = response.content.find((b) => b.type === "text");
    if (!text || text.type !== "text") throw new HttpsError("unavailable", "empty_response");
    const parsed = JSON.parse(text.text) as Record<string, unknown>;
    const mistakes: Mistake[] = [];
    for (const m of Array.isArray(parsed.mistakes) ? parsed.mistakes : []) {
      if (typeof m !== "object" || m === null) continue;
      const r = m as Record<string, unknown>;
      const original = clean(r.original, MAX_CHARS);
      const corrected = clean(r.corrected, MAX_CHARS);
      if (!original || !corrected || same(original, corrected)) continue;
      mistakes.push({ original, corrected, explanation_tr: clean(r.explanation_tr, 300) });
      if (mistakes.length >= MAX_MISTAKES) break;
    }
    // Recasts the partner made during the chat, which the review may have skipped.
    for (const m of inFlow) {
      if (mistakes.length >= MAX_MISTAKES) break;
      if (!mistakes.some((x) => same(x.original, m.original))) mistakes.push(m);
    }
    return { mistakes, summary_tr: clean(parsed.summary_tr, 600), weak_words, remaining };
  } catch (error) {
    await refundReportQuota(db, uid, now).catch(() => undefined);
    if (error instanceof HttpsError) throw error;
    if (error instanceof Anthropic.RateLimitError) throw new HttpsError("unavailable", "upstream_busy");
    if (error instanceof Anthropic.APIError) {
      logger.error(`Anthropic API error ${error.status}: ${error.message}`);
      throw new HttpsError("unavailable", "upstream_error");
    }
    logger.error("conversationReport failed", error);
    throw new HttpsError("internal", "internal_error");
  }
}
