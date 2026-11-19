// Doğal konuşma: the streaming voice conversation (callable `talk`).
//
// The app sends { scenarioId | mode: "free" | characterId, topic?, level?,
// goal?, voice?, messages } and, while Claude is still writing, receives
// stream chunks
//   { type: "sentence", i, text, audio: base64 MP3 | null }
// one per finished sentence of the partner's reply, in order, so the phone can
// start speaking the first sentence right away. The final result is
//   { reply, correction, tip_tr, done, remaining, free, voice, talkSecondsLeft,
//     timing, sentences? }
// (`sentences` only for clients that cannot stream).
//
// Free users keep their 3 messages a day (shared with `converse`) and hear the
// phone's own voice (audio: null). Premium gets the neural voice and a
// fair-use time of FAIR_USE_MINUTES a day.
import Anthropic from "@anthropic-ai/sdk";
import { Firestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { HttpsError } from "firebase-functions/v2/https";

import {
  ClaudeClient,
  DAILY_MESSAGE_LIMIT,
  FREE_DAILY_MESSAGE_LIMIT,
  hasPremium,
  MODEL,
  parseMessages,
  refundQuota,
  takeQuota,
} from "./converse.js";
import { resolveContext, talkSystemPrompt } from "./talk_context.js";
import {
  addVoiceUsage,
  CharBudget,
  DAILY_TTS_CHARS,
  rateForLevel,
  readVoiceUsage,
  speakableText,
  speakCached,
  TtsClient,
  voiceFor,
} from "./tts.js";

/** Premium fair use: estimated minutes of conversation per Turkish day. */
export const FAIR_USE_MINUTES = 45;
export const FAIR_USE_SECONDS = FAIR_USE_MINUTES * 60;

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

const REFUSAL_REPLY = "Sorry, let's talk about something else. What else is on your mind?";

export interface TalkSentence {
  type: "sentence";
  i: number;
  text: string;
  /** Base64 MP3 in the neural voice, or null: the phone speaks it itself. */
  audio: string | null;
}

export interface TalkResult {
  reply: string;
  correction: string;
  tip_tr: string;
  done: boolean;
  remaining: number;
  free: boolean;
  /** "neural" when sentences carry audio, "device" when the phone should speak. */
  voice: "neural" | "device";
  /** Premium fair-use seconds left today (null for free users). */
  talkSecondsLeft: number | null;
  /** Server-side milliseconds: first sentence text, first audio, whole turn. */
  timing: { firstTextMs: number | null; firstAudioMs: number | null; totalMs: number };
  sentences?: TalkSentence[];
}

/**
 * Pulls the "reply" string out of the model's JSON while it is still being
 * written, so speech can start before the JSON is complete.
 */
export class ReplyExtractor {
  private buf = "";
  private start = -1; // index just after the opening quote of the value
  private pos = 0; // next unread index inside the value
  private ended = false;

  /** Feeds more JSON text; returns the newly decoded reply characters. */
  push(delta: string): string {
    this.buf += delta;
    if (this.ended) return "";
    if (this.start < 0) {
      const m = /"reply"\s*:\s*"/.exec(this.buf);
      if (!m) return "";
      this.start = this.pos = m.index + m[0].length;
    }
    let out = "";
    while (this.pos < this.buf.length) {
      const c = this.buf[this.pos];
      if (c === '"') {
        this.ended = true;
        break;
      }
      if (c !== "\\") {
        out += c;
        this.pos++;
        continue;
      }
      // An escape: wait until it is complete.
      const next = this.buf[this.pos + 1];
      if (next === undefined) break;
      if (next === "u") {
        const hex = this.buf.slice(this.pos + 2, this.pos + 6);
        if (hex.length < 4) break;
        out += String.fromCharCode(parseInt(hex, 16));
        this.pos += 6;
        continue;
      }
      out += ({ n: " ", t: " ", r: "", b: "", f: "" } as Record<string, string>)[next] ?? next;
      this.pos += 2;
    }
    return out;
  }

  get done(): boolean {
    return this.ended;
  }
}

const ABBREVIATIONS = /\b(?:Mr|Mrs|Ms|Dr|St|Prof|Mt|vs|etc|e\.g|i\.e)\.$/i;

/**
 * Cuts streamed text into sentences for speech. A sentence ends at . ! or ?
 * (plus closing quotes) followed by a space; very short pieces ("Oh!") wait
 * for the next sentence so the voice does not sound choppy.
 */
export class SentenceSplitter {
  private buf = "";

  push(text: string): string[] {
    this.buf += text;
    const out: string[] = [];
    const re = /[.!?]+["')\]]*\s+/g;
    let from = 0;
    let m: RegExpExecArray | null;
    while ((m = re.exec(this.buf))) {
      const end = m.index + m[0].length;
      const candidate = this.buf.slice(from, end).trim();
      if (ABBREVIATIONS.test(this.buf.slice(from, m.index + 1).trim())) continue;
      if (candidate.split(/\s+/).length < 2) continue; // too short: join with the next
      out.push(candidate);
      from = end;
    }
    this.buf = this.buf.slice(from);
    return out;
  }

  /** Whatever is left once the reply is complete. */
  flush(): string[] {
    const rest = this.buf.trim();
    this.buf = "";
    return rest ? [rest] : [];
  }
}

/** Rough seconds of conversation one turn took: the learner speaking slowly, the partner, short gaps. */
export function estimateTurnSeconds(learnerText: string, reply: string, rate: number): number {
  const learnerWords = learnerText.trim().split(/\s+/).filter(Boolean).length;
  return Math.round(learnerWords / 1.6 + reply.length / (14 * rate) + 3);
}

type Send = (chunk: TalkSentence) => unknown;

export async function talk(
  db: Firestore,
  client: ClaudeClient,
  tts: TtsClient,
  uid: string,
  data: unknown,
  now: Date,
  send: Send | null,
  clock: () => number = Date.now,
): Promise<TalkResult> {
  const t0 = clock();
  const body = (typeof data === "object" && data !== null ? data : {}) as Record<string, unknown>;
  const ctx = resolveContext(body);
  const messages = parseMessages(body.messages);
  if (!ctx || !messages) throw new HttpsError("invalid-argument", "invalid_request");

  const free = !(await hasPremium(db, uid, now));
  const usage = free ? null : await readVoiceUsage(db, uid, now);
  if (usage && usage.talkSeconds >= FAIR_USE_SECONDS) {
    throw new HttpsError("resource-exhausted", "fair_use");
  }
  const remaining = await takeQuota(db, uid, now, free ? FREE_DAILY_MESSAGE_LIMIT : DAILY_MESSAGE_LIMIT, free);

  const voice = voiceFor(body.voice, ctx.voice);
  const rate = rateForLevel(ctx.level);
  const sentences: TalkSentence[] = [];
  let firstTextMs: number | null = null;
  let firstAudioMs: number | null = null;
  let neural = !free;
  const budget = new CharBudget(DAILY_TTS_CHARS - (usage?.ttsChars ?? 0));
  let chain: Promise<void> = Promise.resolve();

  const emit = (raw: string) => {
    const text = speakableText(raw);
    if (!text) return;
    if (firstTextMs === null) firstTextMs = clock() - t0;
    const i = sentences.length;
    const sentence: TalkSentence = { type: "sentence", i, text, audio: null };
    sentences.push(sentence);
    // Synthesis runs in parallel; sentences go out in order.
    const audio = neural
      ? speakCached(db, tts, budget, { text, voiceName: voice.name, languageCode: voice.languageCode, rate }, now)
      : Promise.resolve(null);
    chain = chain.then(async () => {
      const out = await audio;
      if (out?.audio) {
        sentence.audio = out.audio.toString("base64");
        if (firstAudioMs === null) firstAudioMs = clock() - t0;
      } else if (out) {
        neural = false; // cap or TTS failure: the phone speaks the rest of this turn
      }
      await send?.(sentence);
    });
  };

  try {
    const stream = await client.beta.messages.create({
      model: MODEL,
      max_tokens: 1000,
      stream: true,
      betas: ["server-side-fallback-2026-07-01"],
      fallbacks: "default",
      cache_control: { type: "ephemeral" },
      // No thinking: a spoken reply must start fast.
      thinking: { type: "between_tools" },
      system: talkSystemPrompt(ctx),
      messages,
      output_config: {
        effort: "low",
        format: { type: "json_schema", schema: REPLY_SCHEMA },
      },
    });

    const extractor = new ReplyExtractor();
    const splitter = new SentenceSplitter();
    let json = "";
    let stopReason: string | null = null;
    let flushed = false;
    for await (const event of stream) {
      if (event.type === "content_block_delta") {
        const delta = event.delta as { type?: string; text?: string };
        if (delta.type === "text_delta" && delta.text) {
          json += delta.text;
          if (!flushed) {
            for (const s of splitter.push(extractor.push(delta.text))) emit(s);
            // The reply is complete: speak its last sentence now, not after the correction fields.
            if (extractor.done) {
              flushed = true;
              for (const s of splitter.flush()) emit(s);
            }
          }
        }
      } else if (event.type === "message_delta") {
        stopReason = (event.delta as { stop_reason?: string | null }).stop_reason ?? stopReason;
      }
    }

    let reply = "";
    let correction = "";
    let tipTr = "";
    let done = false;
    if (stopReason === "refusal") {
      reply = sentences.length ? sentences.map((s) => s.text).join(" ") : REFUSAL_REPLY;
      if (!sentences.length) emit(REFUSAL_REPLY);
    } else {
      for (const s of splitter.flush()) emit(s);
      const parsed = JSON.parse(json) as Record<string, unknown>;
      reply = speakableText(String(parsed.reply ?? ""));
      correction = String(parsed.correction ?? "").trim();
      tipTr = String(parsed.tip_tr ?? "").trim();
      done = Boolean(parsed.done);
      if (!sentences.length && reply) emit(reply);
    }
    if (!reply) throw new HttpsError("unavailable", "empty_response");
    await chain;

    const learner = messages[messages.length - 1].content;
    const used = free
      ? null
      : (
          await addVoiceUsage(db, uid, now, {
            ttsChars: budget.spent,
            talkSeconds: estimateTurnSeconds(learner, reply, rate),
          })
        ).talkSeconds;
    const timing = { firstTextMs, firstAudioMs, totalMs: clock() - t0 };
    logger.info("talk_turn", { kind: ctx.kind, id: ctx.id, free, neural, sentences: sentences.length, ...timing });
    return {
      reply,
      correction,
      tip_tr: tipTr,
      done,
      remaining,
      free,
      voice: neural && sentences.some((s) => s.audio) ? "neural" : "device",
      talkSecondsLeft: used === null ? null : Math.max(0, FAIR_USE_SECONDS - used),
      timing,
      ...(send ? {} : { sentences }),
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
    logger.error("talk failed", error);
    throw new HttpsError("internal", "internal_error");
  }
}
