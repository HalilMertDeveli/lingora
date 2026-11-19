// Neural voices for the Premium voice conversation: Google Cloud
// Text-to-Speech (Chirp 3 HD) through Application Default Credentials of the
// functions' service account. Needs the Cloud Text-to-Speech API enabled on
// the project (texttospeech.googleapis.com).
//
// Identical phrases are cached in Firestore `ttsCache/{sha256}` (an MP3 of a
// short sentence is a few KB). Each Premium user has a daily character
// budget for new synthesis (`voiceUsage/{uid}`); cached phrases are free.
// ElevenLabs is deliberately NOT used here: its credits are for the course audio.
import { createHash } from "node:crypto";

import { Firestore, Timestamp } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { HttpsError } from "firebase-functions/v2/https";
import { GoogleAuth } from "google-auth-library";

import { hasPremium } from "./converse.js";
import { DEFAULT_VOICE, VOICES } from "./talk_context.js";
import { dayKey } from "./week.js";

/** New (uncached) characters a Premium user may synthesize per Turkish day (~40 min of speech). */
export const DAILY_TTS_CHARS = 30_000;
/** Longest text one `speak` call accepts. */
export const MAX_SPEAK_CHARS = 400;
/** Cached audio is dropped after this many days (Firestore TTL on `expireAt`). */
export const CACHE_DAYS = 60;

export interface TtsRequest {
  text: string;
  voiceName: string;
  languageCode: string;
  /** 0.25..2; 1 is normal speed. */
  rate: number;
}

/** Turns text into MP3 bytes. Faked in tests; never called for real there. */
export interface TtsClient {
  synthesize(req: TtsRequest): Promise<Buffer>;
}

const TTS_URL = "https://texttospeech.googleapis.com/v1/text:synthesize";

/** The real Google Cloud TTS client (ADC). */
export function googleTts(): TtsClient {
  const auth = new GoogleAuth({ scopes: ["https://www.googleapis.com/auth/cloud-platform"] });
  return {
    async synthesize(req) {
      const client = await auth.getClient();
      const res = await client.request<{ audioContent?: string }>({
        url: TTS_URL,
        method: "POST",
        data: {
          input: { text: req.text },
          voice: { languageCode: req.languageCode, name: req.voiceName },
          audioConfig: {
            audioEncoding: "MP3",
            ...(req.rate !== 1 ? { speakingRate: req.rate } : {}),
          },
        },
        timeout: 10_000,
      });
      const b64 = res.data.audioContent;
      if (!b64) throw new Error("tts: empty audio");
      return Buffer.from(b64, "base64");
    },
  };
}

/** Speaking rate for a CEFR level: slower for beginners. */
export function rateForLevel(level: string): number {
  return level === "A1" ? 0.85 : level === "A2" ? 0.92 : 1;
}

/** Plain text worth speaking: no markup, collapsed spaces. */
export function speakableText(raw: string): string {
  return raw.replace(/[*_#`<>[\]{}]/g, "").replace(/\s+/g, " ").trim();
}

export function cacheKey(req: TtsRequest): string {
  return createHash("sha256").update(`${req.voiceName}|${req.rate.toFixed(2)}|${req.text}`).digest("hex");
}

export function voiceFor(id: unknown, fallback = DEFAULT_VOICE): { id: string; name: string; languageCode: string } {
  const key = typeof id === "string" && VOICES[id] ? id : VOICES[fallback] ? fallback : DEFAULT_VOICE;
  return { id: key, ...VOICES[key] };
}

/** Today's voice usage of one learner (`voiceUsage/{uid}`). */
export interface VoiceUsage {
  /** New characters synthesized today. */
  ttsChars: number;
  /** Estimated seconds of voice conversation today (talk.ts fair use). */
  talkSeconds: number;
}

export async function readVoiceUsage(db: Firestore, uid: string, now: Date): Promise<VoiceUsage> {
  const u = (await db.doc(`voiceUsage/${uid}`).get()).data();
  if (u?.day !== dayKey(now)) return { ttsChars: 0, talkSeconds: 0 };
  return { ttsChars: (u.ttsChars as number) ?? 0, talkSeconds: (u.talkSeconds as number) ?? 0 };
}

/** Adds one turn's usage in a single write (one per turn, so sentences never wait on each other). */
export async function addVoiceUsage(db: Firestore, uid: string, now: Date, add: VoiceUsage): Promise<VoiceUsage> {
  const ref = db.doc(`voiceUsage/${uid}`);
  const day = dayKey(now);
  return db.runTransaction(async (tx) => {
    const u = (await tx.get(ref)).data();
    const today = u?.day === day;
    const next = {
      day,
      ttsChars: (today ? ((u?.ttsChars as number) ?? 0) : 0) + add.ttsChars,
      talkSeconds: (today ? ((u?.talkSeconds as number) ?? 0) : 0) + add.talkSeconds,
    };
    tx.set(ref, next);
    return next;
  });
}

/** New-synthesis characters still allowed in this turn; spent locally, saved once. */
export class CharBudget {
  constructor(public left: number) {}
  spent = 0;
  take(n: number): boolean {
    if (n > this.left) return false;
    this.left -= n;
    this.spent += n;
    return true;
  }
  giveBack(n: number): void {
    this.left += n;
    this.spent -= n;
  }
}

export type SpeakOutcome = { audio: Buffer; cached: boolean } | { audio: null; reason: "cap" | "error" };

/**
 * MP3 for [req]: from the cache, or synthesized (spending [budget]) and
 * cached. Never throws: on failure the app uses the phone's own voice.
 */
export async function speakCached(
  db: Firestore,
  tts: TtsClient,
  budget: CharBudget,
  req: TtsRequest,
  now: Date,
): Promise<SpeakOutcome> {
  const ref = db.doc(`ttsCache/${cacheKey(req)}`);
  try {
    const hit = (await ref.get()).data();
    if (hit?.audio) return { audio: Buffer.from(hit.audio as Uint8Array), cached: true };
  } catch (e) {
    logger.warn("tts cache read failed", e);
  }
  if (!budget.take(req.text.length)) return { audio: null, reason: "cap" };
  try {
    const audio = await tts.synthesize(req);
    ref
      .set({
        audio,
        voice: req.voiceName,
        chars: req.text.length,
        at: Timestamp.fromDate(now),
        expireAt: Timestamp.fromMillis(now.getTime() + CACHE_DAYS * 86_400_000),
      })
      .catch((e) => logger.warn("tts cache write failed", e));
    return { audio, cached: false };
  } catch (e) {
    logger.error("tts synthesize failed", e);
    budget.giveBack(req.text.length); // nothing was heard
    return { audio: null, reason: "error" };
  }
}

/**
 * Callable `speak` { text, voice?, rate? } -> { audio (base64 MP3) | null,
 * cached, reason? }. Premium only: free users hear the phone's voice.
 */
export async function speak(
  db: Firestore,
  tts: TtsClient,
  uid: string,
  data: unknown,
  now: Date,
): Promise<{ audio: string | null; cached: boolean; reason?: string }> {
  const body = (typeof data === "object" && data !== null ? data : {}) as Record<string, unknown>;
  const text = speakableText(typeof body.text === "string" ? body.text : "");
  if (!text || text.length > MAX_SPEAK_CHARS) throw new HttpsError("invalid-argument", "invalid_request");
  if (!(await hasPremium(db, uid, now))) throw new HttpsError("permission-denied", "premium_required");
  const voice = voiceFor(body.voice);
  const rate = typeof body.rate === "number" && body.rate >= 0.5 && body.rate <= 1.5 ? body.rate : 1;
  const usage = await readVoiceUsage(db, uid, now);
  const budget = new CharBudget(DAILY_TTS_CHARS - usage.ttsChars);
  const out = await speakCached(db, tts, budget, { text, voiceName: voice.name, languageCode: voice.languageCode, rate }, now);
  if (budget.spent) await addVoiceUsage(db, uid, now, { ttsChars: budget.spent, talkSeconds: 0 });
  return out.audio
    ? { audio: out.audio.toString("base64"), cached: out.cached }
    : { audio: null, cached: false, reason: out.reason };
}
