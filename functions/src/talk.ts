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

/**
 * Live voice turns use the fast model; the end-of-call karne
 * (conversation_report.ts) keeps the stronger MODEL (Sonnet).
 */
export const TALK_MODEL = "claude-haiku-5-5";
/** A reply is 1-3 short sentences plus the silent correction: small is fast. */
export const TALK_MAX_TOKENS = 400;

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

/** Words before a clause break (comma etc.) that make the FIRST chunk worth speaking on its own. */
export const FIRST_CLAUSE_WORDS = 3;
/** Without any punctuation, the first chunk goes after this many words. */
export const FIRST_CHUNK_MAX_WORDS = 8;
/** Later chunks break at a clause only when the sentence is this long. */
export const LONG_CLAUSE_WORDS = 12;

const words = (t: string) => t.trim().split(/\s+/).filter(Boolean).length;

/**
 * Cuts streamed text into pieces for speech. The first piece goes out as
 * early as it sounds natural: at the first sentence end, the first clause
 * break (comma, semicolon, colon, dash) after a few words, or after
 * [FIRST_CHUNK_MAX_WORDS] words. Later pieces are whole sentences (long ones
 * break at a clause). Tiny pieces ("Oh!") wait so the voice is not choppy.
 */
export class SentenceSplitter {
  private buf = "";
  private first = true;

  push(text: string): string[] {
    this.buf += text;
    const out: string[] = [];
    for (let cut = this.nextCut(); cut > 0; cut = this.nextCut()) {
      out.push(this.buf.slice(0, cut).trim());
      this.buf = this.buf.slice(cut);
      this.first = false;
    }
    return out;
  }

  /** Index just after the next piece in [buf], or -1. */
  private nextCut(): number {
    const buf = this.buf;
    let best = -1;
    const take = (i: number) => {
      if (best < 0 || i < best) best = i;
    };
    const sentence = /[.!?]+["')\]]*\s+/g;
    for (let m: RegExpExecArray | null; (m = sentence.exec(buf)); ) {
      const head = buf.slice(0, m.index + 1).trim();
      if (ABBREVIATIONS.test(head) || words(head) < 2) continue;
      take(m.index + m[0].length);
      break;
    }
    const clause = /[,;:—–]\s+/g;
    const minWords = this.first ? FIRST_CLAUSE_WORDS : LONG_CLAUSE_WORDS;
    for (let m: RegExpExecArray | null; (m = clause.exec(buf)); ) {
      if (words(buf.slice(0, m.index)) < minWords) continue;
      take(m.index + m[0].length);
      break;
    }
    if (this.first) {
      const w = /\S+\s+/g;
      let n = 0;
      for (let m: RegExpExecArray | null; (m = w.exec(buf)); ) {
        if (++n === FIRST_CHUNK_MAX_WORDS) {
          take(m.index + m[0].length);
          break;
        }
      }
    }
    return best;
  }

  /** Whatever is left once the reply is complete. */
  flush(): string[] {
    const rest = this.buf.trim();
    this.buf = "";
    return rest ? [rest] : [];
  }
}

const wordList = (t: string) => t.toLowerCase().match(/[a-z0-9']+/g) ?? [];

/**
 * The model's correction only when it is about the learner's LAST message:
 * not empty, not the same sentence again, and sharing most of its words. The
 * fast model sometimes repeats an earlier turn's correction; that would pin
 * the wrong fix on this sentence in the karne.
 */
export function relevantCorrection(learner: string, correction: string): string {
  const fix = correction.trim();
  const said = wordList(learner);
  const fixed = wordList(fix);
  if (!fix || said.length === 0 || said.join(" ") === fixed.join(" ")) return "";
  const inFix = new Set(fixed);
  const shared = said.filter((w) => inFix.has(w)).length;
  return shared / said.length >= 0.5 ? fix : "";
}

/** Rough seconds of conversation one turn took: the learner speaking slowly, the partner, short gaps. */
export function estimateTurnSeconds(learnerText: string, reply: string, rate: number): number {
  const learnerWords = learnerText.trim().split(/\s+/).filter(Boolean).length;
  return Math.round(learnerWords / 1.6 + reply.length / (14 * rate) + 3);
}

type Send = (chunk: TalkSentence) => unknown;

/**
 * `talk` with { warm: true }: the call is starting. Wakes this instance and
 * opens the TTS and Claude connections now (a free token count), so the
 * learner's first turn does not pay for it.
 */
export async function warmTalk(client: ClaudeClient, tts: TtsClient): Promise<{ warm: true }> {
  await Promise.all([
    tts.warm?.().catch(() => undefined),
    client.beta.messages
      .countTokens?.({ model: TALK_MODEL, messages: [{ role: "user", content: "hi" }] })
      .catch(() => undefined),
  ]);
  return { warm: true };
}

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
      model: TALK_MODEL,
      max_tokens: TALK_MAX_TOKENS,
      stream: true,
      cache_control: { type: "ephemeral" },
      // No thinking: a spoken reply must start fast. (Haiku 5.5 has no
      // server-side refusal fallback; a refusal gets REFUSAL_REPLY below.)
      thinking: { type: "disabled" },
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
      let parsed: Record<string, unknown>;
      try {
        parsed = JSON.parse(json) as Record<string, unknown>;
      } catch {
        // Cut off after the reply (max_tokens): keep what was said, skip the feedback.
        if (!extractor.done || !sentences.length) throw new HttpsError("unavailable", "empty_response");
        parsed = { reply: sentences.map((s) => s.text).join(" ") };
      }
      reply = speakableText(String(parsed.reply ?? ""));
      correction = relevantCorrection(messages[messages.length - 1].content, String(parsed.correction ?? ""));
      tipTr = correction ? String(parsed.tip_tr ?? "").trim() : "";
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
