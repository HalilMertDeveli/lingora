// Çenebaz Kurumsal sales: quote requests from the /kurumsal page and 30-day
// trial seat codes (docs/kurumsal-satis.md).
//
//   leads/{id}        {org, name, phone, email, students, city, message,
//                      consentVersion, consentAt, createdAt, status, note, source}
//                     Written only by submitLead, read only by Çenebaz staff
//                     through leadList (catch-all rule: no client access).
//   leadRate/{key}    {day, count, expireAt}: per-IP (hashed) and global daily
//                     counters. No IP address is stored.
//
// Trial codes are ordinary licenseCodes (docs/kurumlar.md) with trial: true and
// an end date 30 days ahead, so they stop working by themselves: the rules
// refuse claiming an expired code and the app ends Premium at expiresAt.
import { createHash, randomInt } from "node:crypto";

import { DocumentSnapshot, FieldValue, Firestore, Timestamp } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";

import { Caller, isLingoraAdmin } from "./orgs.js";

/** Bump when the consent text on hosting/sayfalar/kurumsal.html changes. */
export const CONSENT_VERSION = "2026-11-19";
export const PER_IP_DAILY = 3;
export const GLOBAL_DAILY = 100;
export const LEAD_LIST_LIMIT = 200;
export const TRIAL_DAYS = 30;
export const MAX_TRIAL_STUDENTS = 60;
export const MAX_TRIAL_TEACHERS = 3;

export const LEAD_STATUSES = ["yeni", "arandi", "deneme", "musteri", "kapandi"] as const;
export type LeadStatus = (typeof LEAD_STATUSES)[number];

/** Pages allowed to post the form; localhost for the emulator and `firebase serve`. */
export const ALLOWED_ORIGINS = ["https://dilbaz-3392e.web.app", "https://dilbaz-3392e.firebaseapp.com"];
const LOCAL_ORIGIN = /^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/;

const DAY_MS = 24 * 60 * 60 * 1000;
const LICENSE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // [A-HJ-NP-Z2-9] in firestore.rules
const LICENSE_CODE_LENGTH = 12;

export interface LeadInput {
  org: string;
  name: string;
  phone: string;
  email: string;
  students: number;
  city: string;
  message: string;
}

type Rec = Record<string, unknown>;
const rec = (v: unknown): Rec => (typeof v === "object" && v !== null && !Array.isArray(v) ? (v as Rec) : {});

/** Trimmed single-line text without control characters. */
function text(v: unknown, max: number, multiline = false): string {
  if (typeof v !== "string") return "";
  const cleaned = multiline
    ? v.replace(/\r\n?/g, "\n").replace(/[\u0000-\u0009\u000B-\u001F\u007F]/g, "")
    : v.replace(/[\u0000-\u001F\u007F]/g, " ");
  return cleaned.replace(/[ \t]+/g, " ").trim().slice(0, max);
}

/** Turkish day key (UTC+3), YYYY-MM-DD. */
export function trDay(now: Date): string {
  return new Date(now.getTime() + 3 * 60 * 60 * 1000).toISOString().slice(0, 10);
}

/**
 * Checks the form. Returns the clean lead or the list of bad fields
 * (field names as in the form).
 */
export function parseLead(raw: unknown): { lead: LeadInput } | { errors: string[] } {
  const d = rec(raw);
  const errors: string[] = [];
  const org = text(d.org, 80);
  const name = text(d.name, 60);
  const phoneRaw = text(d.phone, 30);
  const email = text(d.email, 100).toLowerCase();
  const city = text(d.city, 40);
  const message = text(d.message, 1000, true);
  const studentsNum = typeof d.students === "string" ? Number(d.students.trim()) : d.students;

  if (org.length < 2) errors.push("org");
  if (name.length < 2) errors.push("name");
  const digits = phoneRaw.replace(/[\s()+.-]/g, "");
  const phoneOk = phoneRaw === "" || /^\d{10,13}$/.test(digits);
  if (!phoneOk) errors.push("phone");
  const emailOk = email === "" || /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email);
  if (!emailOk) errors.push("email");
  if (phoneOk && emailOk && phoneRaw === "" && email === "") errors.push("contact");
  if (typeof studentsNum !== "number" || !Number.isInteger(studentsNum) || studentsNum < 1 || studentsNum > 100000) {
    errors.push("students");
  }
  if (city.length < 2) errors.push("city");
  if (d.consent !== true) errors.push("consent");
  if (errors.length) return { errors };
  return { lead: { org, name, phone: phoneRaw, email, students: studentsNum as number, city, message } };
}

export function originAllowed(origin: string | undefined): boolean {
  if (!origin) return true; // Not a browser (curl): rate limits still apply.
  return ALLOWED_ORIGINS.includes(origin) || (process.env.FUNCTIONS_EMULATOR === "true" && LOCAL_ORIGIN.test(origin));
}

/** One more submission today for this IP and overall; false when over a limit. */
export async function takeLeadQuota(db: Firestore, ip: string, now: Date): Promise<boolean> {
  const day = trDay(now);
  // Hashed with the day: today's counter cannot be linked to tomorrow's.
  const key = createHash("sha256").update(`${day}|${ip}`).digest("hex").slice(0, 32);
  const ipRef = db.doc(`leadRate/ip_${key}`);
  const allRef = db.doc("leadRate/global");
  const expireAt = Timestamp.fromMillis(now.getTime() + 2 * DAY_MS);
  return db.runTransaction(async (tx) => {
    const [ipSnap, allSnap] = await Promise.all([tx.get(ipRef), tx.get(allRef)]);
    const used = (s: DocumentSnapshot) => (s.get("day") === day ? (s.get("count") as number) : 0);
    const ipUsed = used(ipSnap);
    const allUsed = used(allSnap);
    if (ipUsed >= PER_IP_DAILY || allUsed >= GLOBAL_DAILY) return false;
    tx.set(ipRef, { day, count: ipUsed + 1, expireAt });
    tx.set(allRef, { day, count: allUsed + 1 });
    return true;
  });
}

export interface LeadRequest {
  method: string;
  origin?: string;
  ip: string;
  body: unknown;
}

export interface LeadResponse {
  status: number;
  body: { ok: boolean; error?: string; fields?: string[] };
}

/** The whole submitLead endpoint, apart from HTTP plumbing (sales_api.ts). */
export async function handleLeadRequest(db: Firestore, req: LeadRequest, now: Date): Promise<LeadResponse> {
  if (req.method !== "POST") return { status: 405, body: { ok: false, error: "method" } };
  if (!originAllowed(req.origin)) return { status: 403, body: { ok: false, error: "origin" } };
  const body = rec(req.body);
  // Honeypot: a hidden field people never fill. Pretend success.
  if (typeof body.website === "string" && body.website.trim() !== "") return { status: 200, body: { ok: true } };
  const parsed = parseLead(body);
  if ("errors" in parsed) return { status: 400, body: { ok: false, error: "invalid", fields: parsed.errors } };
  if (!(await takeLeadQuota(db, req.ip || "unknown", now))) {
    return { status: 429, body: { ok: false, error: "rate_limited" } };
  }
  await db.collection("leads").add({
    ...parsed.lead,
    consentVersion: CONSENT_VERSION,
    consentAt: Timestamp.fromDate(now),
    createdAt: Timestamp.fromDate(now),
    status: "yeni" satisfies LeadStatus,
    note: "",
    source: "kurumsal-sayfa",
  });
  return { status: 200, body: { ok: true } };
}

async function requireStaff(db: Firestore, caller: Caller): Promise<void> {
  if (!(await isLingoraAdmin(db, caller))) throw new HttpsError("permission-denied", "lingora_admin_only");
}

const ms = (v: unknown) => (v instanceof Timestamp ? v.toMillis() : 0);

/** {} -> {leads: [...]} newest first (staff only). */
export async function listLeads(db: Firestore, caller: Caller, _data: unknown, _now: Date) {
  await requireStaff(db, caller);
  const snap = await db.collection("leads").orderBy("createdAt", "desc").limit(LEAD_LIST_LIMIT).get();
  return {
    leads: snap.docs.map((d) => ({
      id: d.id,
      org: d.get("org") ?? "",
      name: d.get("name") ?? "",
      phone: d.get("phone") ?? "",
      email: d.get("email") ?? "",
      students: d.get("students") ?? 0,
      city: d.get("city") ?? "",
      message: d.get("message") ?? "",
      status: d.get("status") ?? "yeni",
      note: d.get("note") ?? "",
      trialBatch: d.get("trialBatch") ?? null,
      createdAt: ms(d.get("createdAt")),
    })),
  };
}

function leadId(d: Rec): string {
  const id = d.id;
  if (typeof id !== "string" || !/^[A-Za-z0-9]{1,40}$/.test(id)) throw new HttpsError("invalid-argument", "bad_id");
  return id;
}

/** {id, status?, note?} -> {ok} (staff only). */
export async function updateLead(db: Firestore, caller: Caller, data: unknown, now: Date) {
  await requireStaff(db, caller);
  const d = rec(data);
  const ref = db.doc(`leads/${leadId(d)}`);
  const patch: Rec = { updatedAt: Timestamp.fromDate(now) };
  if (d.status !== undefined) {
    if (!LEAD_STATUSES.includes(d.status as LeadStatus)) throw new HttpsError("invalid-argument", "bad_status");
    patch.status = d.status;
  }
  if (d.note !== undefined) patch.note = text(d.note, 500, true);
  try {
    await ref.update(patch);
  } catch {
    throw new HttpsError("not-found", "lead_not_found");
  }
  return { ok: true };
}

/** {id} -> {ok} (staff only): KVKK deletion request or spam. */
export async function deleteLead(db: Firestore, caller: Caller, data: unknown, _now: Date) {
  await requireStaff(db, caller);
  await db.doc(`leads/${leadId(rec(data))}`).delete();
  return { ok: true };
}

/** End of the Turkish day [days] after [now], as the licence scripts use. */
export function trialEnd(now: Date, days = TRIAL_DAYS): Date {
  const day = trDay(new Date(now.getTime() + days * DAY_MS));
  return new Date(Date.parse(`${day}T23:59:59+03:00`));
}

const newLicenseCode = () =>
  Array.from({ length: LICENSE_CODE_LENGTH }, () => LICENSE_ALPHABET[randomInt(LICENSE_ALPHABET.length)]).join("");

/**
 * {org, students, teachers, leadId?} -> {batch, expiresAt, codes: [{code, role}]}
 * (staff only). Seat codes for a free 30-day trial.
 */
export async function createTrial(db: Firestore, caller: Caller, data: unknown, now: Date) {
  await requireStaff(db, caller);
  const d = rec(data);
  const org = text(d.org, 60);
  if (org.length < 2) throw new HttpsError("invalid-argument", "bad_org");
  const students = d.students;
  const teachers = d.teachers;
  if (typeof students !== "number" || !Number.isInteger(students) || students < 0 || students > MAX_TRIAL_STUDENTS) {
    throw new HttpsError("invalid-argument", "bad_students");
  }
  if (typeof teachers !== "number" || !Number.isInteger(teachers) || teachers < 1 || teachers > MAX_TRIAL_TEACHERS) {
    throw new HttpsError("invalid-argument", "bad_teachers");
  }
  const lead = d.leadId === undefined || d.leadId === null ? null : leadId({ id: d.leadId });
  if (lead && !(await db.doc(`leads/${lead}`).get()).exists) throw new HttpsError("not-found", "lead_not_found");

  const end = trialEnd(now);
  const expiresAt = Timestamp.fromDate(end);
  const slug = org
    .toLocaleLowerCase("tr")
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/ı/g, "i")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "")
    .slice(0, 30);
  const batchId = `deneme-${slug || "kurum"}-${trDay(now)}-${randomInt(1000, 10000)}`;
  const roles = [...Array<string>(teachers).fill("teacher"), ...Array<string>(students).fill("student")];
  const codes: { code: string; role: string }[] = [];
  const batch = db.batch();
  for (const role of roles) {
    let code: string;
    do code = newLicenseCode();
    while (codes.some((c) => c.code === code) || (await db.doc(`licenseCodes/${code}`).get()).exists);
    batch.create(db.doc(`licenseCodes/${code}`), {
      org,
      role,
      expiresAt,
      batch: batchId,
      claimedBy: null,
      claimedAt: null,
      trial: true,
      createdBy: caller.uid,
    });
    codes.push({ code, role });
  }
  if (lead) {
    batch.update(db.doc(`leads/${lead}`), { status: "deneme", trialBatch: batchId, updatedAt: FieldValue.serverTimestamp() });
  }
  await batch.commit();
  return { batch: batchId, expiresAt: end.getTime(), codes };
}
