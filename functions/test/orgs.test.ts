import assert from "node:assert/strict";
import { beforeEach, test } from "node:test";

import { Timestamp } from "firebase-admin/firestore";

import {
  assignmentDone,
  Caller,
  createAssignment,
  createClass,
  createJoinCode,
  createOrg,
  deleteAssignment,
  deleteClass,
  getMyOrg,
  joinOrg,
  leaveOrg,
  listOrgs,
  normalizeCode,
  orgReport,
  progressSummary,
  removeMember,
  revokeJoinCode,
  rotateJoinCode,
  setClassMember,
  setMemberRole,
  updateOrg,
} from "../src/orgs.js";
import { adminDb, clearFirestore, rejectsWith } from "./helpers.js";

const db = adminDb();
const now = new Date("2026-11-10T09:00:00Z"); // 12:00 in Istanbul
const DAY = 24 * 60 * 60 * 1000;
const staff: Caller = { uid: "staff", claims: { isLingoraAdmin: true } };
const u = (uid: string): Caller => ({ uid });

beforeEach(clearFirestore);

/** An org with [seats] seats, its admin "boss" and a teacher "tina" with class c. */
async function setup(seats = 3) {
  const { orgId, adminCode } = await createOrg(
    db,
    staff,
    { name: "Deniz Otel", type: "kurum", seats, planExpiresAt: now.getTime() + 30 * DAY },
    now,
  );
  await joinOrg(db, u("boss"), { code: adminCode, displayName: "Patron" }, now);
  const { code: teacherCode } = await createJoinCode(db, u("boss"), { orgId, role: "teacher" }, now);
  await joinOrg(db, u("tina"), { code: teacherCode, displayName: "Tina Hoca" }, now);
  const { classId } = await createClass(db, u("tina"), { orgId, name: "Resepsiyon" }, now);
  const { code: classCode } = await createJoinCode(db, u("tina"), { orgId, role: "member", classId }, now);
  return { orgId, adminCode, classId, classCode };
}

const org = async (orgId: string) => (await db.doc(`orgs/${orgId}`).get()).data()!;
const ent = async (uid: string) => (await db.doc(`entitlements/${uid}`).get()).data();

test("only Lingora staff can create and update orgs", async () => {
  const data = { name: "Okul", type: "okul", seats: 10, planExpiresAt: now.getTime() + DAY };
  await rejectsWith(createOrg(db, u("eve"), data, now), "permission-denied", "lingora_admin_only");
  await rejectsWith(createOrg(db, staff, { ...data, type: "x" }, now), "invalid-argument");
  await rejectsWith(createOrg(db, staff, { ...data, seats: 0 }, now), "invalid-argument");
  await rejectsWith(createOrg(db, staff, { ...data, planExpiresAt: now.getTime() - 1 }, now), "invalid-argument");

  // The seeded list works as well as the custom claim.
  await db.doc("config/lingoraAdmins").set({ uids: ["owner"] });
  const { orgId, adminCode } = await createOrg(db, u("owner"), data, now);
  assert.equal(normalizeCode(adminCode), adminCode);
  assert.equal((await org(orgId)).seatsUsed, 0);
  await rejectsWith(updateOrg(db, u("eve"), { orgId, seats: 20 }, now), "permission-denied");
  const updated = await updateOrg(db, u("owner"), { orgId, seats: 20 }, now);
  assert.equal(updated.seats, 20);

  const listed = await listOrgs(db, u("owner"), {}, now);
  assert.equal(listed.lingoraAdmin, true);
  assert.equal(listed.orgs.length, 1);
  assert.deepEqual(await listOrgs(db, u("eve"), {}, now), { lingoraAdmin: false, orgs: [] });
});

test("joining uses a seat and grants Premium until the plan ends; admins use none", async () => {
  const { orgId, classCode, classId } = await setup();
  const o = await org(orgId);
  assert.equal(o.seatsUsed, 1); // tina; the admin has no seat
  assert.equal(await ent("boss"), undefined);

  const r = await joinOrg(db, u("ali"), { code: classCode.toLowerCase().replace(/(....)/, "$1-"), displayName: " Ali  Y " }, now);
  assert.deepEqual(r, { orgId, orgName: "Deniz Otel", orgType: "kurum", role: "member" });
  assert.equal((await org(orgId)).seatsUsed, 2);
  const e = (await ent("ali"))!;
  assert.equal(e.active, true);
  assert.equal(e.source, "org");
  assert.equal(e.orgId, orgId);
  assert.equal(e.expiresAt.toMillis(), now.getTime() + 30 * DAY);
  const m = (await db.doc(`orgs/${orgId}/members/ali`).get()).data()!;
  assert.equal(m.displayName, "Ali Y");
  assert.deepEqual(m.classIds, [classId]);
  assert.deepEqual((await db.doc("memberships/ali").get()).data()!.orgId, orgId);

  // Joining again is idempotent and does not use another seat.
  await joinOrg(db, u("ali"), { code: classCode, displayName: "Ali" }, now);
  assert.equal((await org(orgId)).seatsUsed, 2);

  await joinOrg(db, u("veli"), { code: classCode, displayName: "Veli" }, now);
  await rejectsWith(joinOrg(db, u("can"), { code: classCode, displayName: "Can" }, now), "resource-exhausted", "no_seats");
});

test("join errors: bad code, expired plan, another org", async () => {
  const { orgId, classCode } = await setup();
  await rejectsWith(joinOrg(db, u("a"), { code: "ZZZZZZZZ", displayName: "A" }, now), "not-found", "invalid_code");
  await rejectsWith(joinOrg(db, u("a"), { code: "short", displayName: "A" }, now), "invalid-argument");
  await rejectsWith(joinOrg(db, u("a"), { code: classCode, displayName: "" }, now), "invalid-argument");
  await rejectsWith(
    joinOrg(db, u("a"), { code: classCode, displayName: "A" }, new Date(now.getTime() + 31 * DAY)),
    "failed-precondition",
    "plan_expired",
  );
  const other = await createOrg(db, staff, { name: "B", type: "okul", seats: 5, planExpiresAt: now.getTime() + DAY }, now);
  await joinOrg(db, u("a"), { code: other.adminCode, displayName: "A" }, now);
  await rejectsWith(joinOrg(db, u("a"), { code: classCode, displayName: "A" }, now), "failed-precondition", "already_in_org");
  assert.equal((await org(orgId)).seatsUsed, 1);
});

test("a longer store subscription is not shortened by the org", async () => {
  const { classCode } = await setup();
  const far = Timestamp.fromMillis(now.getTime() + 300 * DAY);
  await db.doc("entitlements/ali").set({ active: true, source: "play", productId: "lingora_premium_yearly", expiresAt: far });
  await joinOrg(db, u("ali"), { code: classCode, displayName: "Ali" }, now);
  await leaveOrg(db, u("ali"), {}, now);
  const e = (await ent("ali"))!;
  assert.equal(e.source, "play");
  assert.equal(e.active, true);
  assert.equal(e.expiresAt.toMillis(), far.toMillis());
});

test("org grants merge: other writers' fields (exam packs) survive join and leave", async () => {
  const { classCode } = await setup();
  await db.doc("entitlements/ali").set({ packs: { yds: true } });
  await joinOrg(db, u("ali"), { code: classCode, displayName: "Ali" }, now);
  assert.deepEqual((await ent("ali"))!.packs, { yds: true });
  assert.equal((await ent("ali"))!.source, "org");
  await leaveOrg(db, u("ali"), {}, now);
  assert.deepEqual((await ent("ali"))!.packs, { yds: true });
  assert.equal((await ent("ali"))!.active, false);
});

test("leaving does not touch Premium that another source took over", async () => {
  const { classCode } = await setup();
  await joinOrg(db, u("ali"), { code: classCode, displayName: "Ali" }, now);
  const far = Timestamp.fromMillis(now.getTime() + 300 * DAY);
  await db.doc("entitlements/ali").set({ source: "family", expiresAt: far, family: { ownerUid: "mom" } }, { merge: true });
  await leaveOrg(db, u("ali"), {}, now);
  const e = (await ent("ali"))!;
  assert.equal(e.active, true);
  assert.equal(e.source, "family");
});

test("leaving and removal free the seat and end the org Premium", async () => {
  const { orgId, classCode } = await setup();
  await joinOrg(db, u("ali"), { code: classCode, displayName: "Ali" }, now);
  await joinOrg(db, u("veli"), { code: classCode, displayName: "Veli" }, now);
  assert.equal((await org(orgId)).seatsUsed, 3);

  await leaveOrg(db, u("ali"), {}, now);
  assert.equal((await org(orgId)).seatsUsed, 2);
  assert.equal((await ent("ali"))!.active, false);
  assert.equal((await db.doc("memberships/ali").get()).exists, false);
  await rejectsWith(leaveOrg(db, u("ali"), {}, now), "not-found");

  await rejectsWith(removeMember(db, u("tina"), { orgId, uid: "veli" }, now), "permission-denied");
  await rejectsWith(removeMember(db, u("boss"), { orgId, uid: "boss" }, now), "invalid-argument", "use_leave");
  await removeMember(db, u("boss"), { orgId, uid: "veli" }, now);
  assert.equal((await org(orgId)).seatsUsed, 1);
  assert.equal((await ent("veli"))!.active, false);
  // The freed seat can be used again.
  await joinOrg(db, u("can"), { code: classCode, displayName: "Can" }, now);
});

test("roles: who may hand out which code", async () => {
  const { orgId, classId, classCode } = await setup();
  await joinOrg(db, u("ali"), { code: classCode, displayName: "Ali" }, now);
  await rejectsWith(createJoinCode(db, u("tina"), { orgId, role: "teacher" }, now), "permission-denied");
  await rejectsWith(createJoinCode(db, u("tina"), { orgId, role: "teacher", classId }, now), "permission-denied");
  await rejectsWith(createJoinCode(db, u("ali"), { orgId, role: "member", classId }, now), "permission-denied");
  await rejectsWith(createJoinCode(db, u("eve"), { orgId, role: "member" }, now), "permission-denied");
  await rejectsWith(createJoinCode(db, u("boss"), { orgId, role: "admin", classId }, now), "invalid-argument");
  // Lingora staff may manage any org.
  await createJoinCode(db, staff, { orgId, role: "admin" }, now);

  // Rotate retires the old code; revoke just retires it.
  const { code: fresh } = await rotateJoinCode(db, u("tina"), { code: classCode }, now);
  assert.notEqual(fresh, classCode);
  await rejectsWith(joinOrg(db, u("x"), { code: classCode, displayName: "X" }, now), "not-found", "invalid_code");
  await rejectsWith(revokeJoinCode(db, u("ali"), { code: fresh }, now), "permission-denied");
  await revokeJoinCode(db, u("boss"), { code: fresh }, now);
  await rejectsWith(joinOrg(db, u("x"), { code: fresh, displayName: "X" }, now), "not-found", "invalid_code");
});

test("role changes move seats and Premium", async () => {
  const { orgId, classCode } = await setup(2);
  await joinOrg(db, u("ali"), { code: classCode, displayName: "Ali" }, now);
  assert.equal((await org(orgId)).seatsUsed, 2);
  await rejectsWith(setMemberRole(db, u("tina"), { orgId, uid: "ali", role: "teacher" }, now), "permission-denied");
  await rejectsWith(
    setMemberRole(db, u("boss"), { orgId, uid: "boss", role: "member" }, now),
    "failed-precondition",
    "last_admin",
  );
  const { code: adminCode } = await createJoinCode(db, u("boss"), { orgId, role: "admin" }, now);
  await joinOrg(db, u("ann"), { code: adminCode, displayName: "Ann" }, now);
  await rejectsWith(setMemberRole(db, u("boss"), { orgId, uid: "ann", role: "member" }, now), "resource-exhausted", "no_seats");
  await removeMember(db, u("boss"), { orgId, uid: "ann" }, now);

  await setMemberRole(db, u("boss"), { orgId, uid: "ali", role: "admin" }, now);
  assert.equal((await org(orgId)).seatsUsed, 1);
  assert.equal((await ent("ali"))!.active, false);
  assert.equal((await db.doc("memberships/ali").get()).data()!.role, "admin");

  // Two admins now, so boss may step down (and takes the free seat).
  await setMemberRole(db, u("boss"), { orgId, uid: "boss", role: "member" }, now);
  assert.equal((await ent("boss"))!.active, true);
  await rejectsWith(setMemberRole(db, u("ali"), { orgId, uid: "ali", role: "member" }, now), "failed-precondition", "last_admin");
});

test("plan renewal moves members' Premium; lapsing ends it", async () => {
  const { orgId, classCode } = await setup();
  await joinOrg(db, u("ali"), { code: classCode, displayName: "Ali" }, now);
  await joinOrg(db, u("veli"), { code: classCode, displayName: "Veli" }, now);
  await leaveOrg(db, u("veli"), {}, now);
  const renewed = now.getTime() + 400 * DAY;
  await updateOrg(db, staff, { orgId, planExpiresAt: renewed }, now);
  assert.equal((await ent("ali"))!.expiresAt.toMillis(), renewed);
  assert.equal((await ent("tina"))!.expiresAt.toMillis(), renewed);
  assert.equal((await ent("veli"))!.active, false); // left before the renewal

  await updateOrg(db, staff, { orgId, planExpiresAt: now.getTime() - DAY }, now);
  assert.equal((await ent("ali"))!.active, false);
  await rejectsWith(updateOrg(db, staff, { orgId, seats: 1 }, now), "failed-precondition", "seats_below_used");
});

test("classes and assignments: teachers manage only their own", async () => {
  const { orgId, classId, classCode } = await setup();
  await joinOrg(db, u("ali"), { code: classCode, displayName: "Ali" }, now);
  const { classId: other } = await createClass(db, u("boss"), { orgId, name: "Mutfak" }, now);
  const due = now.getTime() + 7 * DAY;
  const base = { orgId, classId, kind: "lesson", targetId: "u1l1", courseId: "tr_en", title: "Selamlaşma", dueAt: due };
  await rejectsWith(createAssignment(db, u("tina"), { ...base, classId: other }, now), "permission-denied", "not_your_class");
  await rejectsWith(createAssignment(db, u("ali"), base, now), "permission-denied");
  await rejectsWith(createAssignment(db, u("tina"), { ...base, kind: "video" }, now), "invalid-argument");
  await rejectsWith(createAssignment(db, u("tina"), { ...base, courseId: undefined }, now), "invalid-argument");
  await rejectsWith(createAssignment(db, u("tina"), { ...base, dueAt: now.getTime() - 1 }, now), "invalid-argument");
  const { assignmentId } = await createAssignment(db, u("tina"), base, now);
  await createAssignment(db, u("boss"), { ...base, classId: other, kind: "exam", targetId: "yds", title: "YDS denemesi" }, now);

  await rejectsWith(setClassMember(db, u("tina"), { orgId, classId: other, uid: "ali", add: true }, now), "permission-denied");
  await setClassMember(db, u("boss"), { orgId, classId: other, uid: "ali", add: true }, now);
  assert.deepEqual((await db.doc(`orgs/${orgId}/members/ali`).get()).get("classIds"), [classId, other]);

  await rejectsWith(deleteClass(db, u("tina"), { orgId, classId: other }, now), "permission-denied");
  await deleteClass(db, u("boss"), { orgId, classId: other }, now);
  assert.deepEqual((await db.doc(`orgs/${orgId}/members/ali`).get()).get("classIds"), [classId]);
  assert.equal((await db.collection(`orgs/${orgId}/assignments`).get()).size, 1);

  await rejectsWith(deleteAssignment(db, u("ali"), { orgId, assignmentId }, now), "permission-denied");
  await deleteAssignment(db, u("tina"), { orgId, assignmentId }, now);
  assert.equal((await db.collection(`orgs/${orgId}/assignments`).get()).size, 0);
});

test("assignment completion follows the synced progress", () => {
  const p = { completed: { u1l1: 2, gl_present_simple: 1, exam_yds: 1 }, examBest: { lgs: 70 } };
  assert.equal(assignmentDone({ kind: "lesson", targetId: "u1l1" }, p), true);
  assert.equal(assignmentDone({ kind: "lesson", targetId: "u1l2" }, p), false);
  assert.equal(assignmentDone({ kind: "grammar", targetId: "present_simple" }, p), true);
  assert.equal(assignmentDone({ kind: "exam", targetId: "lgs" }, p), true);
  assert.equal(assignmentDone({ kind: "exam", targetId: "yds" }, p), false); // practice only, no mock
  assert.equal(assignmentDone({ kind: "lesson", targetId: "u1l1" }, undefined), false);
});

test("progress summary: effective streak and last 7 days of XP", () => {
  const s = progressSummary(
    {
      lessonsDone: 12,
      totalXp: 340,
      streak: 4,
      lastActiveDay: "2026-11-09",
      xpByDay: { "2026-11-10": 5, "2026-11-04": 10, "2026-11-03": 100 },
    },
    now,
  );
  assert.deepEqual(s, { lessonsDone: 12, totalXp: 340, streak: 4, lastActiveDay: "2026-11-09", weekXp: 15 });
  assert.equal(progressSummary({ streak: 4, lastActiveDay: "2026-11-07" }, now).streak, 0);
  assert.deepEqual(progressSummary(undefined, now), {
    lessonsDone: 0,
    totalXp: 0,
    streak: 0,
    lastActiveDay: null,
    weekXp: 0,
  });
});

test("report: aggregated progress only, never diary or notes (KVKK)", async () => {
  const { orgId, classId, classCode } = await setup(10);
  await joinOrg(db, u("ali"), { code: classCode, displayName: "Ali" }, now);
  const { code: plain } = await createJoinCode(db, u("boss"), { orgId, role: "member" }, now);
  await joinOrg(db, u("ayse"), { code: plain, displayName: "Ayşe" }, now); // in no class
  await createAssignment(
    db,
    u("tina"),
    { orgId, classId, kind: "grammar", targetId: "past_simple", title: "Past simple", dueAt: now.getTime() + DAY },
    now,
  );
  await createAssignment(
    db,
    u("tina"),
    { orgId, classId, kind: "exam", targetId: "lgs", title: "LGS", dueAt: now.getTime() + 2 * DAY },
    now,
  );
  const secret = "GIZLI-GUNLUK-METNI";
  await db.doc("users/ali").set({
    progress: {
      totalXp: 120,
      lessonsDone: 6,
      streak: 3,
      lastActiveDay: "2026-11-10",
      xpByDay: { "2026-11-10": 20 },
      completed: { gl_past_simple: 1 },
      diary: { "2026-11-10": secret },
      customWords: [{ en: secret, tr: secret }],
      mistakes: [secret],
      errorStats: { [secret]: 1 },
    },
    displayName: "Ali",
    updatedAt: Timestamp.fromDate(now),
  });

  await rejectsWith(orgReport(db, u("ali"), { orgId }, now), "permission-denied");
  await rejectsWith(orgReport(db, u("eve"), { orgId }, now), "permission-denied");

  const admin = await orgReport(db, u("boss"), { orgId }, now);
  assert.equal(JSON.stringify(admin).includes(secret), false);
  assert.equal(admin.org.seatsUsed, 3);
  assert.deepEqual(admin.members.map((m) => m.uid).sort(), ["ali", "ayse", "boss", "tina"]);
  const ali = admin.members.find((m) => m.uid === "ali")!;
  assert.deepEqual(
    Object.keys(ali).sort(),
    [
      "assignments",
      "classIds",
      "displayName",
      "joinedAt",
      "lastActiveDay",
      "lessonsDone",
      "role",
      "streak",
      "synced",
      "totalXp",
      "uid",
      "weekXp",
    ],
  );
  assert.equal(ali.totalXp, 120);
  assert.equal(ali.weekXp, 20);
  assert.equal(ali.streak, 3);
  assert.equal(ali.synced, true);
  assert.deepEqual(Object.values(ali.assignments).sort(), ["done", "open"]);
  assert.equal(admin.members.find((m) => m.uid === "ayse")!.synced, false);
  const grammar = admin.assignments.find((a) => a.kind === "grammar")!;
  assert.deepEqual([grammar.done, grammar.total], [1, 1]);
  assert.equal(admin.codes.length >= 2, true);
  assert.equal(admin.classes[0].teacherName, "Tina Hoca");

  // The teacher only sees her class.
  const teacher = await orgReport(db, u("tina"), { orgId }, now);
  assert.equal(teacher.viewerRole, "teacher");
  assert.deepEqual(teacher.members.map((m) => m.uid), ["ali"]);
  assert.equal(teacher.codes.every((c) => c.classId === classId), true);
  await rejectsWith(orgReport(db, u("tina"), { orgId, classId: "nope" }, now), "permission-denied");

  // Past the due date an unfinished assignment is late.
  const later = await orgReport(db, u("boss"), { orgId }, new Date(now.getTime() + 3 * DAY));
  assert.deepEqual(Object.values(later.members.find((m) => m.uid === "ali")!.assignments).sort(), ["done", "late"]);
});

test("getMyOrg: a learner sees the org and their own assignments", async () => {
  assert.deepEqual(await getMyOrg(db, u("ali"), {}, now), { org: null });
  const { orgId, classId, classCode } = await setup();
  await joinOrg(db, u("ali"), { code: classCode, displayName: "Ali" }, now);
  await createAssignment(
    db,
    u("tina"),
    { orgId, classId, kind: "lesson", targetId: "u1l2", courseId: "tr_en", title: "Tanışma", dueAt: now.getTime() + DAY },
    now,
  );
  const mine = await getMyOrg(db, u("ali"), {}, now);
  assert.equal(mine.org?.name, "Deniz Otel");
  assert.equal(mine.role, "member");
  assert.deepEqual(mine.classes, [{ id: classId, name: "Resepsiyon" }]);
  assert.equal(mine.assignments?.length, 1);
  assert.equal(mine.assignments![0].className, "Resepsiyon");
  assert.equal(mine.assignments![0].status, "open");
  assert.equal(mine.assignments![0].courseId, "tr_en");
  // Seats and member lists are not part of the learner view.
  assert.equal("seats" in mine.org!, false);
  assert.equal("members" in mine, false);
});
