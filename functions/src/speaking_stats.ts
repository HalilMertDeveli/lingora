// Speaking stats for teachers (Dilmaç Kurumsal, docs/kurumsal-satis.md).
//
// Every voice-coach karne (conversationReport) adds one conversation to
//   speakingStats/{uid}   {conversations, minutes, lastAt, lastSummary,
//                          recentMistakes: [{original, corrected}], weakWords: {word: n}}
// which only the server reads and writes (catch-all rule). A teacher sees a
// short copy of it only for students who joined their class:
//   classes/{code}/speaking/{uid}  (teacherView, written here for each code in
//                                   classLinks/{uid} whose members/{uid} exists)
// and an org admin or teacher sees it in orgReport for org members.
//
// Kept apart from converse.ts and conversation_report.ts on purpose: it only
// reads the karne's result and the transcript the learner sent.
import { FieldValue, Firestore, Timestamp } from "firebase-admin/firestore";

import { parseTranscript } from "./conversation_report.js";

/** Rough speaking pace for learners: words (both sides) per minute. */
export const WORDS_PER_MINUTE = 100;
export const MAX_MINUTES_PER_CONVERSATION = 30;
export const RECENT_MISTAKES = 5;
export const MAX_WEAK_WORDS = 20;
export const MAX_CLASS_LINKS = 5;
/** conversationReport's answer when Claude declined: not a summary worth keeping. */
const NO_KARNE = "Bu sohbet için karne hazırlanamadı";

export interface SpeakingMistake {
  original: string;
  corrected: string;
}

/** What a teacher or org admin may see. No transcript, no explanations. */
export interface SpeakingView {
  conversations: number;
  minutes: number;
  /** Milliseconds, 0 when never. */
  lastAt: number;
  lastSummary: string;
  /** The latest corrected sentences, newest first (at most 3). */
  recentMistakes: SpeakingMistake[];
  /** Words the recognizer struggled with most often (at most 5). */
  weakWords: string[];
}

export interface KarneResult {
  mistakes: { original: string; corrected: string }[];
  summary_tr: string;
  weak_words: { word: string }[];
}

const cut = (s: unknown, max: number) => (typeof s === "string" ? s.trim().slice(0, max) : "");
const count = (v: unknown) => (typeof v === "number" && Number.isFinite(v) && v > 0 ? Math.floor(v) : 0);

/** Estimated length of a practice conversation from its word count, 1..30 minutes. */
export function estimateMinutes(messages: unknown): number {
  const lines = parseTranscript(messages);
  if (!lines) return 0;
  const words = lines.reduce((n, l) => n + (l.content.match(/\S+/g)?.length ?? 0), 0);
  return Math.min(MAX_MINUTES_PER_CONVERSATION, Math.max(1, Math.round(words / WORDS_PER_MINUTE)));
}

/** speakingStats doc -> the teacher's view. */
export function teacherView(raw: Record<string, unknown> | undefined): SpeakingView {
  const d = raw ?? {};
  const mistakes = Array.isArray(d.recentMistakes) ? d.recentMistakes : [];
  const weak = typeof d.weakWords === "object" && d.weakWords !== null ? (d.weakWords as Record<string, unknown>) : {};
  return {
    conversations: count(d.conversations),
    minutes: count(d.minutes),
    lastAt: d.lastAt instanceof Timestamp ? d.lastAt.toMillis() : 0,
    lastSummary: cut(d.lastSummary, 600),
    recentMistakes: mistakes
      .filter((m): m is Record<string, unknown> => typeof m === "object" && m !== null)
      .map((m) => ({ original: cut(m.original, 160), corrected: cut(m.corrected, 160) }))
      .filter((m) => m.original && m.corrected)
      .slice(0, 3),
    weakWords: Object.entries(weak)
      .map(([w, n]) => [w, count(n)] as const)
      .filter(([, n]) => n > 0)
      .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
      .slice(0, 5)
      .map(([w]) => w),
  };
}

/**
 * Adds one finished conversation to the learner's stats and refreshes the
 * copy in every class they joined. [data] is the request the learner sent to
 * conversationReport, [report] its answer.
 */
export async function recordSpeaking(
  db: Firestore,
  uid: string,
  data: unknown,
  report: KarneResult,
  now: Date,
): Promise<SpeakingView> {
  const body = (typeof data === "object" && data !== null ? data : {}) as Record<string, unknown>;
  const minutes = estimateMinutes(body.messages);
  const ref = db.doc(`speakingStats/${uid}`);
  const view = await db.runTransaction(async (tx) => {
    const old = (await tx.get(ref)).data() ?? {};
    const fresh = report.mistakes
      .map((m) => ({ original: cut(m.original, 160), corrected: cut(m.corrected, 160) }))
      .filter((m) => m.original && m.corrected);
    const oldMistakes = Array.isArray(old.recentMistakes) ? (old.recentMistakes as SpeakingMistake[]) : [];
    const weak: Record<string, number> = {};
    for (const [w, n] of Object.entries((old.weakWords as Record<string, unknown>) ?? {})) weak[w] = count(n);
    for (const w of report.weak_words) {
      const word = cut(w.word, 40).toLowerCase();
      if (/^[a-z][a-z'-]*$/.test(word)) weak[word] = (weak[word] ?? 0) + 1;
    }
    const next = {
      conversations: count(old.conversations) + 1,
      minutes: count(old.minutes) + minutes,
      lastAt: Timestamp.fromDate(now),
      lastSummary:
        (report.summary_tr.startsWith(NO_KARNE) ? "" : cut(report.summary_tr, 600)) || cut(old.lastSummary, 600),
      recentMistakes: [...fresh, ...oldMistakes].slice(0, RECENT_MISTAKES),
      weakWords: Object.fromEntries(
        Object.entries(weak)
          .sort((a, b) => b[1] - a[1])
          .slice(0, MAX_WEAK_WORDS),
      ),
      updatedAt: FieldValue.serverTimestamp(),
    };
    tx.set(ref, next);
    return teacherView(next);
  });
  await publishToClasses(db, uid, view, now);
  return view;
}

/** Copies [view] into each class the learner is still a member of. */
export async function publishToClasses(db: Firestore, uid: string, view: SpeakingView, now: Date): Promise<number> {
  const links = (await db.doc(`classLinks/${uid}`).get()).get("codes");
  const codes = (Array.isArray(links) ? links : [])
    .filter((c): c is string => typeof c === "string" && /^[A-HJ-NP-Z2-9]{8}$/.test(c))
    .slice(0, MAX_CLASS_LINKS);
  let n = 0;
  for (const code of codes) {
    // Only while the student is in that class (they or the teacher may have left it).
    if (!(await db.doc(`classes/${code}/members/${uid}`).get()).exists) continue;
    await db.doc(`classes/${code}/speaking/${uid}`).set({
      ...view,
      lastAt: view.lastAt ? Timestamp.fromMillis(view.lastAt) : null,
      updatedAt: Timestamp.fromDate(now),
    });
    n++;
  }
  return n;
}

/** Teacher views for org members (orgReport). Members with no conversation are left out. */
export async function speakingFor(db: Firestore, uids: string[]): Promise<Map<string, SpeakingView>> {
  const out = new Map<string, SpeakingView>();
  for (let i = 0; i < uids.length; i += 100) {
    const refs = uids.slice(i, i + 100).map((u) => db.doc(`speakingStats/${u}`));
    if (refs.length === 0) continue;
    for (const s of await db.getAll(...refs)) if (s.exists) out.set(s.id, teacherView(s.data()));
  }
  return out;
}
