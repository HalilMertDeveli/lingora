// AI conversation proxy for the "Konuş" tab (port of the old Supabase Edge
// Function in server/supabase/functions/converse). The app sends
// { scenarioId, messages: [{ role, content }] } and gets back
// { reply, correction, tip_tr, done, remaining }. Premium only, with a daily
// message quota.
import Anthropic from "@anthropic-ai/sdk";
import { FieldValue, Firestore, Timestamp } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { HttpsError } from "firebase-functions/v2/https";

import { SCENARIOS, systemPrompt } from "./scenarios.js";
import { dayKey } from "./week.js";

export const MODEL = "claude-opus-5-5";
export const MAX_MESSAGES = 20;
export const MAX_CHARS = 400;
/** Learner messages per user per Turkish day. */
export const DAILY_MESSAGE_LIMIT = 60;

// The model must answer in exactly this shape.
const REPLY_SCHEMA = {
  type: "object",
  properties: {
    reply: { type: "string" },
    correction: { type: "string" },
    tip_tr: { type: "string" },
    done: { type: "boolean" },
  },
  required: ["reply", "correction", "tip_tr", "done"],
  additionalProperties: false,
};

const REFUSAL_REPLY = {
  reply: "Let's get back to our scene. What would you like to say?",
  correction: "",
  tip_tr: "",
  done: false,
};

export interface ConverseReply {
  reply: string;
  correction: string;
  tip_tr: string;
  done: boolean;
  remaining: number;
}

/** The parts of the Anthropic client this module uses (mockable in tests). */
export type ClaudeClient = Pick<Anthropic, "beta">;

type Message = { role: "user" | "assistant"; content: string };

/** Validates the app's history: alternating turns, ending with the learner. */
export function parseMessages(raw: unknown): Message[] | null {
  if (!Array.isArray(raw) || raw.length === 0) return null;
  const out: Message[] = [];
  for (const m of raw.slice(-MAX_MESSAGES)) {
    if (typeof m !== "object" || m === null) return null;
    const { role, content } = m as Record<string, unknown>;
    if ((role !== "user" && role !== "assistant") || typeof content !== "string") return null;
    const text = content.trim().slice(0, MAX_CHARS);
    if (!text) return null;
    out.push({ role, content: text });
  }
  // The scene opens with the partner's line; the API wants a user turn first,
  // so the opening is folded into a short user preamble.
  if (out[0].role === "assistant") out.unshift({ role: "user", content: "(The scene starts.)" });
  for (let i = 1; i < out.length; i++) {
    if (out[i].role === out[i - 1].role) return null;
  }
  if (out[out.length - 1].role !== "user") return null;
  return out;
}

/** True if entitlements/{uid} grants Premium at [now]. */
export async function hasPremium(db: Firestore, uid: string, now: Date): Promise<boolean> {
  const e = (await db.doc(`entitlements/${uid}`).get()).data();
  const expires = e?.expiresAt as Timestamp | undefined;
  return e?.active === true && !!expires && expires.toMillis() > now.getTime();
}

/** Counts one message against today's quota; returns how many are left. */
async function takeQuota(db: Firestore, uid: string, now: Date): Promise<number> {
  const ref = db.doc(`usage/${uid}`);
  const day = dayKey(now);
  return db.runTransaction(async (tx) => {
    const u = (await tx.get(ref)).data();
    const used = u?.day === day ? ((u.count as number) ?? 0) : 0;
    if (used >= DAILY_MESSAGE_LIMIT) throw new HttpsError("resource-exhausted", "daily_quota");
    tx.set(ref, { day, count: used + 1 });
    return DAILY_MESSAGE_LIMIT - used - 1;
  });
}

async function refundQuota(db: Firestore, uid: string, now: Date): Promise<void> {
  const ref = db.doc(`usage/${uid}`);
  await db.runTransaction(async (tx) => {
    const u = (await tx.get(ref)).data();
    if (u?.day === dayKey(now) && (u.count as number) > 0) tx.update(ref, { count: FieldValue.increment(-1) });
  });
}

export async function converse(
  db: Firestore,
  client: ClaudeClient,
  uid: string,
  data: unknown,
  now: Date,
): Promise<ConverseReply> {
  const body = (typeof data === "object" && data !== null ? data : {}) as Record<string, unknown>;
  const scenario = SCENARIOS[String(body.scenarioId)];
  const messages = parseMessages(body.messages);
  if (!scenario || !messages) throw new HttpsError("invalid-argument", "invalid_request");

  if (!(await hasPremium(db, uid, now))) throw new HttpsError("permission-denied", "premium_required");
  const remaining = await takeQuota(db, uid, now);

  try {
    const response = await client.beta.messages.create({
      model: MODEL,
      max_tokens: 2000,
      // Server-side fallback if a request is declined by a safety classifier.
      betas: ["server-side-fallback-2026-07-01"],
      fallbacks: "default",
      cache_control: { type: "ephemeral" },
      system: systemPrompt(scenario),
      messages,
      output_config: {
        effort: "low", // short chat replies; raise only if quality needs it
        format: { type: "json_schema", schema: REPLY_SCHEMA },
      },
    });

    if (response.stop_reason === "refusal") return { ...REFUSAL_REPLY, remaining };
    const text = response.content.find((b) => b.type === "text");
    if (!text || text.type !== "text") throw new HttpsError("unavailable", "empty_response");
    const parsed = JSON.parse(text.text) as Record<string, unknown>;
    return {
      reply: String(parsed.reply ?? ""),
      correction: String(parsed.correction ?? ""),
      tip_tr: String(parsed.tip_tr ?? ""),
      done: Boolean(parsed.done),
      remaining,
    };
  } catch (error) {
    // A failed turn should not cost the learner a message.
    await refundQuota(db, uid, now).catch(() => undefined);
    if (error instanceof HttpsError) throw error;
    if (error instanceof Anthropic.RateLimitError) throw new HttpsError("unavailable", "upstream_busy");
    if (error instanceof Anthropic.APIError) {
      logger.error(`Anthropic API error ${error.status}: ${error.message}`);
      throw new HttpsError("unavailable", "upstream_error");
    }
    logger.error("converse failed", error);
    throw new HttpsError("internal", "internal_error");
  }
}
