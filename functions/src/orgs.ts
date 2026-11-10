// Lingora Kurumsal: organisations (hotels, companies, schools), seats, join
// codes, classes, assignments and a privacy-filtered progress report.
// Docs: docs/kurumsal.md. Callables are wired in orgs_api.ts.
//
// Firestore, written only here through the Admin SDK (rules keep clients out):
//   orgs/{orgId}                    {name, type, seats, seatsUsed, planExpiresAt, createdBy, createdAt, updatedAt}
//   orgs/{orgId}/members/{uid}      {role, displayName, classIds, seat, joinedAt}
//   orgs/{orgId}/classes/{classId}  {name, teacherUid, createdAt}
//   orgs/{orgId}/assignments/{id}   {classId, kind, targetId, courseId, title, dueAt, createdBy, createdAt}
//   orgCodes/{code}                 {orgId, role, classId, active, uses, createdBy, createdAt}
//   memberships/{uid}               {orgId, role}  (its owner may read it)
//   entitlements/{uid}              Premium with source "org" until the plan ends
//   config/lingoraAdmins            {uids: string[]}  (seeded by the owner)
//
// Privacy (KVKK): the report only ever copies the whitelisted numbers in
// progressSummary(). Diary, notes, custom words, mistakes and chats never
// leave users/{uid}.
import { randomInt } from "node:crypto";

import {
  DocumentReference,
  DocumentSnapshot,
  FieldValue,
  Firestore,
  Timestamp,
  Transaction,
  WriteBatch,
} from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";

export type OrgType = "kurum" | "okul";
export type Role = "admin" | "teacher" | "member";
export type AssignmentKind = "lesson" | "grammar" | "exam";
export type AssignmentStatus = "done" | "open" | "late";

export interface Caller {
  uid: string;
  /** Auth token claims; `isLingoraAdmin: true` marks a Lingora staff account. */
  claims?: Record<string, unknown>;
}

const ROLES: readonly Role[] = ["admin", "teacher", "member"];
const KINDS: readonly AssignmentKind[] = ["lesson", "grammar", "exam"];
const DAY = 24 * 60 * 60 * 1000;
/** Turkey has been on UTC+3 all year since 2016. */
const TR_OFFSET = 3 * 60 * 60 * 1000;
export const MAX_ACTIVE_CODES = 50;
export const MAX_ASSIGNMENTS_PER_CLASS = 200;
export const MAX_CLASSES = 200;
/** Unambiguous characters (no 0/O, 1/I/L). */
const CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
export const CODE_LENGTH = 8;

// ---------------------------------------------------------------- input ----

type Rec = Record<string, unknown>;

function rec(data: unknown): Rec {
  return typeof data === "object" && data !== null && !Array.isArray(data) ? (data as Rec) : {};
}

function bad(reason: string): never {
  throw new HttpsError("invalid-argument", reason);
}

function text(d: Rec, key: string, max: number, opts: { optional?: boolean } = {}): string {
  const v = d[key];
  if (v === undefined && opts.optional) return "";
  if (typeof v !== "string") bad(`invalid_${key}`);
  const t = v.trim().replace(/\s+/g, " ");
  if (t.length < 1 || t.length > max) bad(`invalid_${key}`);
  return t;
}

const ID_RE = /^[A-Za-z0-9_-]{1,64}$/;

function id(d: Rec, key: string, opts: { optional?: boolean } = {}): string {
  const v = d[key];
  if ((v === undefined || v === null || v === "") && opts.optional) return "";
  if (typeof v !== "string" || !ID_RE.test(v)) bad(`invalid_${key}`);
  return v;
}

function int(d: Rec, key: string, min: number, max: number): number {
  const v = d[key];
  if (typeof v !== "number" || !Number.isInteger(v) || v < min || v > max) bad(`invalid_${key}`);
  return v;
}

function oneOf<T extends string>(d: Rec, key: string, values: readonly T[]): T {
  const v = d[key];
  if (typeof v !== "string" || !values.includes(v as T)) bad(`invalid_${key}`);
  return v as T;
}

/** Upper-cases and drops spaces/dashes, so "k7qm-3xpa" works. */
export function normalizeCode(raw: unknown): string {
  if (typeof raw !== "string") bad("invalid_code");
  const c = raw.toUpperCase().replace(/[^A-Z0-9]/g, "");
  if (c.length !== CODE_LENGTH) bad("invalid_code");
  return c;
}

export function newCode(): string {
  let c = "";
  for (let i = 0; i < CODE_LENGTH; i++) c += CODE_ALPHABET[randomInt(CODE_ALPHABET.length)];
  return c;
}

// ---------------------------------------------------------- permissions ----

export async function isLingoraAdmin(db: Firestore, caller: Caller): Promise<boolean> {
  if (caller.claims?.isLingoraAdmin === true) return true;
  const cfg = await db.doc("config/lingoraAdmins").get();
  const uids = cfg.get("uids");
  return Array.isArray(uids) && uids.includes(caller.uid);
}

async function requireLingoraAdmin(db: Firestore, caller: Caller): Promise<void> {
  if (!(await isLingoraAdmin(db, caller))) throw new HttpsError("permission-denied", "lingora_admin_only");
}

interface Access {
  /** "admin" also for Lingora staff, who can manage every org. */
  role: Role;
  staff: boolean;
}

/** The caller's role in [orgId]; throws unless it is one of [allowed]. */
async function requireRole(db: Firestore, orgId: string, caller: Caller, allowed: Role[]): Promise<Access> {
  const [org, member] = await Promise.all([
    db.doc(`orgs/${orgId}`).get(),
    db.doc(`orgs/${orgId}/members/${caller.uid}`).get(),
  ]);
  if (!org.exists) throw new HttpsError("not-found", "org_not_found");
  const role = member.get("role") as Role | undefined;
  if (role && allowed.includes(role)) return { role, staff: false };
  if (await isLingoraAdmin(db, caller)) return { role: "admin", staff: true };
  throw new HttpsError("permission-denied", "not_allowed");
}

/** Admins manage every class; teachers only the ones they teach. */
async function requireClassManager(
  db: Firestore,
  orgId: string,
  classId: string,
  caller: Caller,
): Promise<{ access: Access; cls: DocumentSnapshot }> {
  const access = await requireRole(db, orgId, caller, ["admin", "teacher"]);
  const cls = await db.doc(`orgs/${orgId}/classes/${classId}`).get();
  if (!cls.exists) throw new HttpsError("not-found", "class_not_found");
  if (access.role === "teacher" && cls.get("teacherUid") !== caller.uid) {
    throw new HttpsError("permission-denied", "not_your_class");
  }
  return { access, cls };
}

// --------------------------------------------------------- entitlements ----

/** Members and teachers use a seat and get Premium; admins only manage. */
export const usesSeat = (role: Role): boolean => role !== "admin";

function grantOrgPremium(
  tx: Transaction,
  ref: DocumentReference,
  current: DocumentSnapshot,
  orgId: string,
  planExpiresAt: Timestamp,
): void {
  // Keep a longer Premium from another source (store, family); the org grant would only shorten it.
  if (current.exists && current.get("active") === true && current.get("source") !== "org") {
    const exp = current.get("expiresAt") as Timestamp | undefined;
    if (exp && exp.toMillis() >= planExpiresAt.toMillis()) return;
  }
  // Merge, never a full set: other writers' fields (exam `packs`, `family`) must survive.
  tx.set(
    ref,
    {
      active: true,
      premium: true,
      status: "active",
      productId: "org",
      platform: "org",
      expiresAt: planExpiresAt,
      source: "org",
      orgId,
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
}

function revokeOrgPremium(tx: Transaction, ref: DocumentReference, current: DocumentSnapshot, orgId: string, now: Date) {
  if (!current.exists || current.get("source") !== "org" || current.get("orgId") !== orgId) return;
  tx.set(
    ref,
    {
      active: false,
      premium: false,
      status: "expired",
      expiresAt: Timestamp.fromDate(now),
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
}

// ----------------------------------------------------------------- orgs ----

export interface OrgInfo {
  id: string;
  name: string;
  type: OrgType;
  seats: number;
  seatsUsed: number;
  /** Milliseconds since epoch. */
  planExpiresAt: number;
}

function orgInfo(s: DocumentSnapshot): OrgInfo {
  return {
    id: s.id,
    name: s.get("name"),
    type: s.get("type"),
    seats: s.get("seats"),
    seatsUsed: s.get("seatsUsed") ?? 0,
    planExpiresAt: (s.get("planExpiresAt") as Timestamp).toMillis(),
  };
}

/** {name, type, seats, planExpiresAt} -> {orgId, adminCode}. Lingora staff only. */
export async function createOrg(db: Firestore, caller: Caller, data: unknown, now: Date) {
  await requireLingoraAdmin(db, caller);
  const d = rec(data);
  const name = text(d, "name", 80);
  const type = oneOf<OrgType>(d, "type", ["kurum", "okul"]);
  const seats = int(d, "seats", 1, 10000);
  const planExpiresAt = int(d, "planExpiresAt", now.getTime() + 1, now.getTime() + 3 * 366 * DAY);
  const ref = db.collection("orgs").doc();
  const adminCode = newCode();
  const batch = db.batch();
  batch.set(ref, {
    name,
    type,
    seats,
    seatsUsed: 0,
    planExpiresAt: Timestamp.fromMillis(planExpiresAt),
    createdBy: caller.uid,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  batch.create(db.doc(`orgCodes/${adminCode}`), codeDoc(ref.id, "admin", "", caller.uid));
  await batch.commit();
  return { orgId: ref.id, adminCode };
}

/** {orgId, name?, seats?, planExpiresAt?} -> OrgInfo. Lingora staff only; renews members' Premium. */
export async function updateOrg(db: Firestore, caller: Caller, data: unknown, now: Date) {
  await requireLingoraAdmin(db, caller);
  const d = rec(data);
  const orgId = id(d, "orgId");
  const ref = db.doc(`orgs/${orgId}`);
  const update: Rec = { updatedAt: FieldValue.serverTimestamp() };
  if (d.name !== undefined) update.name = text(d, "name", 80);
  if (d.seats !== undefined) update.seats = int(d, "seats", 1, 10000);
  let expiry: Timestamp | undefined;
  if (d.planExpiresAt !== undefined) {
    expiry = Timestamp.fromMillis(int(d, "planExpiresAt", 0, now.getTime() + 3 * 366 * DAY));
    update.planExpiresAt = expiry;
  }
  await db.runTransaction(async (tx) => {
    const org = await tx.get(ref);
    if (!org.exists) throw new HttpsError("not-found", "org_not_found");
    if (typeof update.seats === "number" && update.seats < (org.get("seatsUsed") ?? 0)) {
      throw new HttpsError("failed-precondition", "seats_below_used");
    }
    tx.update(ref, update);
  });
  if (expiry) await syncOrgEntitlements(db, orgId, expiry, now);
  return orgInfo(await ref.get());
}

/** Moves the org-granted Premium of [orgId]'s current seat holders to the new plan end. */
async function syncOrgEntitlements(db: Firestore, orgId: string, expiry: Timestamp, now: Date) {
  const [ents, members] = await Promise.all([
    db.collection("entitlements").where("orgId", "==", orgId).get(),
    db.collection(`orgs/${orgId}/members`).where("seat", "==", true).get(),
  ]);
  const current = new Set(members.docs.map((m) => m.id));
  // Members who left keep their revoked doc as it is.
  const docs = ents.docs.filter((e) => e.get("source") === "org" && current.has(e.id));
  const active = expiry.toMillis() > now.getTime();
  for (let i = 0; i < docs.length; i += 400) {
    const batch = db.batch();
    for (const e of docs.slice(i, i + 400)) {
      batch.update(e.ref, {
        active,
        premium: active,
        status: active ? "active" : "expired",
        expiresAt: expiry,
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }
}

/** {} -> {lingoraAdmin, orgs}: every org for Lingora staff, else the ones the caller manages. */
export async function listOrgs(db: Firestore, caller: Caller, _data: unknown, _now: Date) {
  if (await isLingoraAdmin(db, caller)) {
    const all = await db.collection("orgs").orderBy("createdAt", "desc").limit(500).get();
    return { lingoraAdmin: true, orgs: all.docs.map(orgInfo) };
  }
  const m = await db.doc(`memberships/${caller.uid}`).get();
  const role = m.get("role") as Role | undefined;
  if (!m.exists || role === "member") return { lingoraAdmin: false, orgs: [] };
  const org = await db.doc(`orgs/${m.get("orgId")}`).get();
  return { lingoraAdmin: false, orgs: org.exists ? [{ ...orgInfo(org), role }] : [] };
}

// ---------------------------------------------------------------- codes ----

function codeDoc(orgId: string, role: Role, classId: string, by: string) {
  return { orgId, role, classId, active: true, uses: 0, createdBy: by, createdAt: FieldValue.serverTimestamp() };
}

async function insertCode(db: Firestore, orgId: string, role: Role, classId: string, by: string): Promise<string> {
  for (let attempt = 0; attempt < 5; attempt++) {
    const code = newCode();
    try {
      await db.doc(`orgCodes/${code}`).create(codeDoc(orgId, role, classId, by));
      return code;
    } catch (e) {
      if ((e as { code?: number }).code !== 6) throw e; // 6 = ALREADY_EXISTS
    }
  }
  throw new HttpsError("internal", "code_collision");
}

/** Who may hand out a code for [role]/[classId]: admins any, teachers member codes for their class. */
async function requireCodeRights(db: Firestore, orgId: string, role: Role, classId: string, caller: Caller) {
  if (classId) {
    const { access } = await requireClassManager(db, orgId, classId, caller);
    if (access.role === "teacher" && role !== "member") throw new HttpsError("permission-denied", "not_allowed");
    return;
  }
  await requireRole(db, orgId, caller, ["admin"]);
}

/** {orgId, role, classId?} -> {code} */
export async function createJoinCode(db: Firestore, caller: Caller, data: unknown, _now: Date) {
  const d = rec(data);
  const orgId = id(d, "orgId");
  const role = oneOf(d, "role", ROLES);
  const classId = id(d, "classId", { optional: true });
  if (classId && role === "admin") bad("invalid_role");
  await requireCodeRights(db, orgId, role, classId, caller);
  const active = await db.collection("orgCodes").where("orgId", "==", orgId).where("active", "==", true).count().get();
  if (active.data().count >= MAX_ACTIVE_CODES) throw new HttpsError("resource-exhausted", "too_many_codes");
  return { code: await insertCode(db, orgId, role, classId, caller.uid) };
}

async function loadCodeForChange(db: Firestore, caller: Caller, data: unknown) {
  const code = normalizeCode(rec(data).code);
  const snap = await db.doc(`orgCodes/${code}`).get();
  if (!snap.exists) throw new HttpsError("not-found", "invalid_code");
  const orgId = snap.get("orgId") as string;
  const role = snap.get("role") as Role;
  const classId = (snap.get("classId") as string) ?? "";
  await requireCodeRights(db, orgId, role, classId, caller);
  return { code, snap, orgId, role, classId };
}

/** {code} -> {ok} */
export async function revokeJoinCode(db: Firestore, caller: Caller, data: unknown, _now: Date) {
  const { snap } = await loadCodeForChange(db, caller, data);
  await snap.ref.update({ active: false });
  return { ok: true };
}

/** {code} -> {code}: retires a code (e.g. after it leaked) and issues a new one with the same role/class. */
export async function rotateJoinCode(db: Firestore, caller: Caller, data: unknown, _now: Date) {
  const { snap, orgId, role, classId } = await loadCodeForChange(db, caller, data);
  await snap.ref.update({ active: false });
  return { code: await insertCode(db, orgId, role, classId, caller.uid) };
}

// ----------------------------------------------------------- membership ----

/** {code, displayName} -> {orgId, orgName, orgType, role} */
export async function joinOrg(db: Firestore, caller: Caller, data: unknown, now: Date) {
  const d = rec(data);
  const code = normalizeCode(d.code);
  const displayName = text(d, "displayName", 40);
  const uid = caller.uid;
  return db.runTransaction(async (tx) => {
    const codeRef = db.doc(`orgCodes/${code}`);
    const codeSnap = await tx.get(codeRef);
    if (!codeSnap.exists || codeSnap.get("active") !== true) throw new HttpsError("not-found", "invalid_code");
    const orgId = codeSnap.get("orgId") as string;
    const role = codeSnap.get("role") as Role;
    const classId = (codeSnap.get("classId") as string) || "";
    const orgRef = db.doc(`orgs/${orgId}`);
    const memberRef = db.doc(`orgs/${orgId}/members/${uid}`);
    const shipRef = db.doc(`memberships/${uid}`);
    const entRef = db.doc(`entitlements/${uid}`);
    const [org, ship, member, ent, cls] = await Promise.all([
      tx.get(orgRef),
      tx.get(shipRef),
      tx.get(memberRef),
      tx.get(entRef),
      classId ? tx.get(db.doc(`orgs/${orgId}/classes/${classId}`)) : Promise.resolve(undefined),
    ]);
    if (!org.exists) throw new HttpsError("not-found", "invalid_code");
    const planExpiresAt = org.get("planExpiresAt") as Timestamp;
    if (planExpiresAt.toMillis() <= now.getTime()) throw new HttpsError("failed-precondition", "plan_expired");
    if (ship.exists && ship.get("orgId") !== orgId) throw new HttpsError("failed-precondition", "already_in_org");
    if (cls && !cls.exists) throw new HttpsError("not-found", "invalid_code");

    const result = { orgId, orgName: org.get("name") as string, orgType: org.get("type") as OrgType };
    if (member.exists) {
      // Already in: a class code just adds the class, the role stays.
      const update: Rec = { displayName };
      if (classId) update.classIds = FieldValue.arrayUnion(classId);
      tx.update(memberRef, update);
      tx.update(codeRef, { uses: FieldValue.increment(1) });
      return { ...result, role: member.get("role") as Role };
    }
    const seat = usesSeat(role);
    if (seat && (org.get("seatsUsed") ?? 0) >= org.get("seats")) {
      throw new HttpsError("resource-exhausted", "no_seats");
    }
    tx.set(memberRef, {
      role,
      displayName,
      classIds: classId ? [classId] : [],
      seat,
      joinedAt: FieldValue.serverTimestamp(),
    });
    tx.set(shipRef, { orgId, role, joinedAt: FieldValue.serverTimestamp() });
    tx.update(codeRef, { uses: FieldValue.increment(1) });
    if (seat) {
      tx.update(orgRef, { seatsUsed: FieldValue.increment(1) });
      grantOrgPremium(tx, entRef, ent, orgId, planExpiresAt);
    }
    return { ...result, role };
  });
}

async function removeFromOrg(db: Firestore, orgId: string, uid: string, now: Date) {
  await db.runTransaction(async (tx) => {
    const memberRef = db.doc(`orgs/${orgId}/members/${uid}`);
    const entRef = db.doc(`entitlements/${uid}`);
    const [member, ent] = await Promise.all([tx.get(memberRef), tx.get(entRef)]);
    if (!member.exists) throw new HttpsError("not-found", "not_a_member");
    tx.delete(memberRef);
    tx.delete(db.doc(`memberships/${uid}`));
    if (member.get("seat") === true) tx.update(db.doc(`orgs/${orgId}`), { seatsUsed: FieldValue.increment(-1) });
    revokeOrgPremium(tx, entRef, ent, orgId, now);
  });
}

/** {} -> {ok}: frees the seat and ends the org Premium. */
export async function leaveOrg(db: Firestore, caller: Caller, _data: unknown, now: Date) {
  const ship = await db.doc(`memberships/${caller.uid}`).get();
  if (!ship.exists) throw new HttpsError("not-found", "not_in_org");
  await removeFromOrg(db, ship.get("orgId"), caller.uid, now);
  return { ok: true };
}

/** {orgId, uid} -> {ok}. Admins only; use leaveOrg for yourself. */
export async function removeMember(db: Firestore, caller: Caller, data: unknown, now: Date) {
  const d = rec(data);
  const orgId = id(d, "orgId");
  const uid = id(d, "uid");
  await requireRole(db, orgId, caller, ["admin"]);
  if (uid === caller.uid) bad("use_leave");
  await removeFromOrg(db, orgId, uid, now);
  return { ok: true };
}

/** {orgId, uid, role} -> {ok}. Admins only. Seats and Premium follow the role. */
export async function setMemberRole(db: Firestore, caller: Caller, data: unknown, now: Date) {
  const d = rec(data);
  const orgId = id(d, "orgId");
  const uid = id(d, "uid");
  const role = oneOf(d, "role", ROLES);
  await requireRole(db, orgId, caller, ["admin"]);
  await db.runTransaction(async (tx) => {
    const orgRef = db.doc(`orgs/${orgId}`);
    const memberRef = db.doc(`orgs/${orgId}/members/${uid}`);
    const entRef = db.doc(`entitlements/${uid}`);
    const [org, member, ent, admins] = await Promise.all([
      tx.get(orgRef),
      tx.get(memberRef),
      tx.get(entRef),
      tx.get(db.collection(`orgs/${orgId}/members`).where("role", "==", "admin").limit(2)),
    ]);
    if (!member.exists) throw new HttpsError("not-found", "not_a_member");
    const old = member.get("role") as Role;
    if (old === role) return;
    if (old === "admin" && admins.size < 2) throw new HttpsError("failed-precondition", "last_admin");
    const hadSeat = member.get("seat") === true;
    const seat = usesSeat(role);
    if (seat && !hadSeat) {
      if ((org.get("seatsUsed") ?? 0) >= org.get("seats")) throw new HttpsError("resource-exhausted", "no_seats");
      tx.update(orgRef, { seatsUsed: FieldValue.increment(1) });
      grantOrgPremium(tx, entRef, ent, orgId, org.get("planExpiresAt"));
    } else if (!seat && hadSeat) {
      tx.update(orgRef, { seatsUsed: FieldValue.increment(-1) });
      revokeOrgPremium(tx, entRef, ent, orgId, now);
    }
    tx.update(memberRef, { role, seat });
    tx.update(db.doc(`memberships/${uid}`), { role });
  });
  return { ok: true };
}

// -------------------------------------------------------------- classes ----

/** {orgId, name, teacherUid?} -> {classId}. Teachers always create classes they teach. */
export async function createClass(db: Firestore, caller: Caller, data: unknown, _now: Date) {
  const d = rec(data);
  const orgId = id(d, "orgId");
  const name = text(d, "name", 60);
  const access = await requireRole(db, orgId, caller, ["admin", "teacher"]);
  let teacherUid = access.role === "teacher" ? caller.uid : id(d, "teacherUid", { optional: true });
  if (teacherUid && access.role === "admin") {
    const t = await db.doc(`orgs/${orgId}/members/${teacherUid}`).get();
    if (!t.exists || t.get("role") === "member") bad("invalid_teacherUid");
  }
  teacherUid ||= "";
  const count = await db.collection(`orgs/${orgId}/classes`).count().get();
  if (count.data().count >= MAX_CLASSES) throw new HttpsError("resource-exhausted", "too_many_classes");
  const ref = db.collection(`orgs/${orgId}/classes`).doc();
  await ref.set({ name, teacherUid, createdAt: FieldValue.serverTimestamp() });
  return { classId: ref.id };
}

/** {orgId, classId} -> {ok}: also drops its assignments and codes. */
export async function deleteClass(db: Firestore, caller: Caller, data: unknown, _now: Date) {
  const d = rec(data);
  const orgId = id(d, "orgId");
  const classId = id(d, "classId");
  const { cls } = await requireClassManager(db, orgId, classId, caller);
  const [members, assignments, codes] = await Promise.all([
    db.collection(`orgs/${orgId}/members`).where("classIds", "array-contains", classId).get(),
    db.collection(`orgs/${orgId}/assignments`).where("classId", "==", classId).get(),
    db.collection("orgCodes").where("orgId", "==", orgId).where("classId", "==", classId).get(),
  ]);
  const writes: ((b: WriteBatch) => void)[] = [
    ...members.docs.map((m) => (b: WriteBatch) =>
      b.update(m.ref, { classIds: FieldValue.arrayRemove(classId) }),
    ),
    ...assignments.docs.map((a) => (b: WriteBatch) => b.delete(a.ref)),
    ...codes.docs.map((c) => (b: WriteBatch) => b.update(c.ref, { active: false })),
    (b: WriteBatch) => b.delete(cls.ref),
  ];
  for (let i = 0; i < writes.length; i += 400) {
    const batch = db.batch();
    writes.slice(i, i + 400).forEach((w) => w(batch));
    await batch.commit();
  }
  return { ok: true };
}

/** {orgId, classId, uid, add} -> {ok} */
export async function setClassMember(db: Firestore, caller: Caller, data: unknown, _now: Date) {
  const d = rec(data);
  const orgId = id(d, "orgId");
  const classId = id(d, "classId");
  const uid = id(d, "uid");
  if (typeof d.add !== "boolean") bad("invalid_add");
  await requireClassManager(db, orgId, classId, caller);
  const ref = db.doc(`orgs/${orgId}/members/${uid}`);
  if (!(await ref.get()).exists) throw new HttpsError("not-found", "not_a_member");
  await ref.update({ classIds: d.add ? FieldValue.arrayUnion(classId) : FieldValue.arrayRemove(classId) });
  return { ok: true };
}

// ---------------------------------------------------------- assignments ----

/**
 * {orgId, classId, kind, targetId, courseId?, title, dueAt} -> {assignmentId}
 * kind "lesson": a course node (targetId = node id, courseId = course asset id)
 * kind "grammar": a grammar-path lesson (targetId = lesson id, done = completed["gl_<id>"])
 * kind "exam": a mock exam set (targetId = exam id, done = examBest[id])
 */
export async function createAssignment(db: Firestore, caller: Caller, data: unknown, now: Date) {
  const d = rec(data);
  const orgId = id(d, "orgId");
  const classId = id(d, "classId");
  const kind = oneOf(d, "kind", KINDS);
  const targetId = id(d, "targetId");
  const courseId = kind === "lesson" ? id(d, "courseId") : "";
  const title = text(d, "title", 120);
  const dueAt = int(d, "dueAt", now.getTime(), now.getTime() + 366 * DAY);
  await requireClassManager(db, orgId, classId, caller);
  const col = db.collection(`orgs/${orgId}/assignments`);
  const count = await col.where("classId", "==", classId).count().get();
  if (count.data().count >= MAX_ASSIGNMENTS_PER_CLASS) {
    throw new HttpsError("resource-exhausted", "too_many_assignments");
  }
  const ref = col.doc();
  await ref.set({
    classId,
    kind,
    targetId,
    courseId,
    title,
    dueAt: Timestamp.fromMillis(dueAt),
    createdBy: caller.uid,
    createdAt: FieldValue.serverTimestamp(),
  });
  return { assignmentId: ref.id };
}

/** {orgId, assignmentId} -> {ok} */
export async function deleteAssignment(db: Firestore, caller: Caller, data: unknown, _now: Date) {
  const d = rec(data);
  const orgId = id(d, "orgId");
  const ref = db.doc(`orgs/${orgId}/assignments/${id(d, "assignmentId")}`);
  const a = await ref.get();
  if (!a.exists) throw new HttpsError("not-found", "assignment_not_found");
  await requireClassManager(db, orgId, a.get("classId"), caller);
  await ref.delete();
  return { ok: true };
}

export interface AssignmentView {
  id: string;
  classId: string;
  kind: AssignmentKind;
  targetId: string;
  courseId: string;
  title: string;
  /** Milliseconds since epoch. */
  dueAt: number;
}

function assignmentView(s: DocumentSnapshot): AssignmentView {
  return {
    id: s.id,
    classId: s.get("classId"),
    kind: s.get("kind"),
    targetId: s.get("targetId"),
    courseId: s.get("courseId") ?? "",
    title: s.get("title"),
    dueAt: (s.get("dueAt") as Timestamp).toMillis(),
  };
}

// ------------------------------------------------------ progress report ----

/** Day key (yyyy-mm-dd) in Turkish time, like the app's dayKey(). */
export function trDayKey(ms: number): string {
  return new Date(ms + TR_OFFSET).toISOString().slice(0, 10);
}

function numMap(v: unknown): Record<string, number> {
  const out: Record<string, number> = {};
  if (typeof v !== "object" || v === null) return out;
  for (const [k, n] of Object.entries(v)) if (typeof n === "number") out[k] = n;
  return out;
}

const num = (v: unknown) => (typeof v === "number" && Number.isFinite(v) ? v : 0);

/** Is [a] done according to the learner's synced progress? */
export function assignmentDone(a: Pick<AssignmentView, "kind" | "targetId">, progress: unknown): boolean {
  const p = rec(progress);
  const completed = numMap(p.completed);
  switch (a.kind) {
    case "lesson":
      return (completed[a.targetId] ?? 0) > 0;
    case "grammar":
      return (completed[`gl_${a.targetId}`] ?? 0) > 0;
    case "exam":
      return a.targetId in numMap(p.examBest);
  }
}

export function assignmentStatus(a: AssignmentView, progress: unknown, now: Date): AssignmentStatus {
  if (assignmentDone(a, progress)) return "done";
  return a.dueAt < now.getTime() ? "late" : "open";
}

export interface ProgressSummary {
  lessonsDone: number;
  totalXp: number;
  /** 0 when the learner missed yesterday, like the app shows it. */
  streak: number;
  lastActiveDay: string | null;
  weekXp: number;
}

/**
 * The only learning data an employer or teacher may see. Everything else in
 * users/{uid} (diary, custom words, mistakes, error stats, reminders) stays
 * private.
 */
export function progressSummary(progress: unknown, now: Date): ProgressSummary {
  const p = rec(progress);
  const today = trDayKey(now.getTime());
  const yesterday = trDayKey(now.getTime() - DAY);
  const last = typeof p.lastActiveDay === "string" && /^\d{4}-\d{2}-\d{2}$/.test(p.lastActiveDay) ? p.lastActiveDay : null;
  const xpByDay = numMap(p.xpByDay);
  let weekXp = 0;
  for (let i = 0; i < 7; i++) weekXp += xpByDay[trDayKey(now.getTime() - i * DAY)] ?? 0;
  return {
    lessonsDone: num(p.lessonsDone),
    totalXp: num(p.totalXp),
    streak: last === today || last === yesterday ? num(p.streak) : 0,
    lastActiveDay: last,
    weekXp,
  };
}

async function loadProgress(db: Firestore, uids: string[]): Promise<Map<string, unknown>> {
  const out = new Map<string, unknown>();
  for (let i = 0; i < uids.length; i += 100) {
    const refs = uids.slice(i, i + 100).map((u) => db.doc(`users/${u}`));
    if (refs.length === 0) continue;
    for (const s of await db.getAll(...refs)) out.set(s.id, s.exists ? s.get("progress") : undefined);
  }
  return out;
}

/** {orgId, classId?} -> the panel's view. Admins see everyone, teachers their classes. */
export async function orgReport(db: Firestore, caller: Caller, data: unknown, now: Date) {
  const d = rec(data);
  const orgId = id(d, "orgId");
  const onlyClass = id(d, "classId", { optional: true });
  const access = await requireRole(db, orgId, caller, ["admin", "teacher"]);
  const [org, classSnap, assignSnap, memberSnap, codeSnap] = await Promise.all([
    db.doc(`orgs/${orgId}`).get(),
    db.collection(`orgs/${orgId}/classes`).get(),
    db.collection(`orgs/${orgId}/assignments`).orderBy("dueAt").get(),
    db.collection(`orgs/${orgId}/members`).get(),
    db.collection("orgCodes").where("orgId", "==", orgId).where("active", "==", true).get(),
  ]);

  let classes = classSnap.docs;
  if (access.role === "teacher") classes = classes.filter((c) => c.get("teacherUid") === caller.uid);
  if (onlyClass) {
    classes = classes.filter((c) => c.id === onlyClass);
    if (classes.length === 0) throw new HttpsError("permission-denied", "not_your_class");
  }
  const visible = new Set(classes.map((c) => c.id));
  const seeAll = access.role === "admin" && !onlyClass;
  const memberDocs = memberSnap.docs.filter(
    (m) => seeAll || (m.get("classIds") as string[] | undefined)?.some((c) => visible.has(c)),
  );
  const assignments = assignSnap.docs.map(assignmentView).filter((a) => visible.has(a.classId));
  const progress = await loadProgress(
    db,
    memberDocs.map((m) => m.id),
  );
  const names = new Map(memberSnap.docs.map((m) => [m.id, m.get("displayName") as string]));

  const members = memberDocs.map((m) => {
    const classIds = ((m.get("classIds") as string[] | undefined) ?? []).filter((c) => seeAll || visible.has(c));
    const p = progress.get(m.id);
    const status: Record<string, AssignmentStatus> = {};
    for (const a of assignments) if (classIds.includes(a.classId)) status[a.id] = assignmentStatus(a, p, now);
    return {
      uid: m.id,
      displayName: m.get("displayName") as string,
      role: m.get("role") as Role,
      classIds,
      joinedAt: (m.get("joinedAt") as Timestamp | undefined)?.toMillis() ?? 0,
      synced: p !== undefined,
      ...progressSummary(p, now),
      assignments: status,
    };
  });

  return {
    org: orgInfo(org),
    viewerRole: access.role,
    staff: access.staff,
    classes: classes.map((c) => ({
      id: c.id,
      name: c.get("name") as string,
      teacherUid: c.get("teacherUid") as string,
      teacherName: names.get(c.get("teacherUid")) ?? "",
      memberCount: memberSnap.docs.filter((m) => (m.get("classIds") as string[] | undefined)?.includes(c.id)).length,
    })),
    assignments: assignments.map((a) => {
      const assigned = members.filter((m) => a.id in m.assignments);
      return { ...a, total: assigned.length, done: assigned.filter((m) => m.assignments[a.id] === "done").length };
    }),
    codes: codeSnap.docs
      .filter((c) => (seeAll ? true : visible.has(c.get("classId"))))
      .map((c) => ({
        code: c.id,
        role: c.get("role") as Role,
        classId: (c.get("classId") as string) ?? "",
        uses: c.get("uses") ?? 0,
      })),
    members,
  };
}

/** {} -> {org: null} or the learner's own org, classes and assignments. */
export async function getMyOrg(db: Firestore, caller: Caller, _data: unknown, now: Date) {
  const ship = await db.doc(`memberships/${caller.uid}`).get();
  if (!ship.exists) return { org: null };
  const orgId = ship.get("orgId") as string;
  const [org, member, user] = await Promise.all([
    db.doc(`orgs/${orgId}`).get(),
    db.doc(`orgs/${orgId}/members/${caller.uid}`).get(),
    db.doc(`users/${caller.uid}`).get(),
  ]);
  if (!org.exists || !member.exists) return { org: null };
  const classIds = (member.get("classIds") as string[] | undefined) ?? [];
  const classes: { id: string; name: string }[] = [];
  const assignments: (AssignmentView & { className: string; status: AssignmentStatus })[] = [];
  for (let i = 0; i < classIds.length; i += 30) {
    const chunk = classIds.slice(i, i + 30);
    const [cs, as] = await Promise.all([
      db.getAll(...chunk.map((c) => db.doc(`orgs/${orgId}/classes/${c}`))),
      db.collection(`orgs/${orgId}/assignments`).where("classId", "in", chunk).get(),
    ]);
    for (const c of cs) if (c.exists) classes.push({ id: c.id, name: c.get("name") });
    for (const a of as.docs) {
      const v = assignmentView(a);
      assignments.push({
        ...v,
        className: "",
        status: assignmentStatus(v, user.get("progress"), now),
      });
    }
  }
  const classNames = new Map(classes.map((c) => [c.id, c.name]));
  for (const a of assignments) a.className = classNames.get(a.classId) ?? "";
  assignments.sort((a, b) => a.dueAt - b.dueAt);
  const info = orgInfo(org);
  return {
    org: { id: info.id, name: info.name, type: info.type, planExpiresAt: info.planExpiresAt },
    role: member.get("role") as Role,
    displayName: member.get("displayName") as string,
    classes,
    assignments,
  };
}
