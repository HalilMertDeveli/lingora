// Security rules for question reports ("Bildir"): reports/{uid}_{n} paired
// with the rate-limit doc reportLimits/{uid}; only staff read and triage.
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { after, before, beforeEach, test } from "node:test";

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  serverTimestamp,
  setDoc,
  setLogLevel,
  Timestamp,
  updateDoc,
  writeBatch,
} from "firebase/firestore";

import { emulatorHost, PROJECT_ID } from "./helpers.js";

let env: RulesTestEnvironment;

before(async () => {
  setLogLevel("silent");
  const [host, port] = emulatorHost().split(":");
  env = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      host,
      port: Number(port),
      rules: readFileSync(resolve(__dirname, "../../../firestore.rules"), "utf8"),
    },
  });
});

after(async () => {
  await env?.cleanup();
});

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const f = ctx.firestore();
    await setDoc(doc(f, "config/lingoraAdmins"), { uids: ["staff"] });
    await setDoc(doc(f, "reports/bob_1"), {
      uid: "bob",
      reason: "unclear",
      questionId: "u1l1#3",
      lessonId: "u1l1",
      appVersion: "0.1.0+1",
      createdAt: Timestamp.now(),
      status: "yeni",
    });
  });
});

/** A guest (anonymous sign-in), like most testers on day one. */
const guest = (uid: string) =>
  env.authenticatedContext(uid, { firebase: { sign_in_provider: "anonymous" } }).firestore();

const report = (uid: string, extra: Record<string, unknown> = {}) => ({
  uid,
  reason: "wrong_answer",
  questionId: "u1l2#4",
  lessonId: "u1l2",
  appVersion: "0.1.0+1",
  answer: "I am agree",
  correct: false,
  question: "Sana katılıyorum.",
  createdAt: serverTimestamp(),
  status: "yeni",
  ...extra,
});

const firstLimit = { windowStart: serverTimestamp(), count: 1, last: serverTimestamp(), n: 1 };

/** The app's write: the limit doc and the report together. */
type Db = ReturnType<typeof guest>;

function file(f: Db, uid: string, n: number, limit: Record<string, unknown>, data = report(uid)) {
  const b = writeBatch(f);
  b.set(doc(f, `reportLimits/${uid}`), limit);
  b.set(doc(f, `reports/${uid}_${n}`), data);
  return b.commit();
}

async function seedLimit(uid: string, l: { windowAgoMs: number; lastAgoMs: number; count: number; n: number }) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const now = Date.now();
    await setDoc(doc(ctx.firestore(), `reportLimits/${uid}`), {
      windowStart: Timestamp.fromMillis(now - l.windowAgoMs),
      last: Timestamp.fromMillis(now - l.lastAgoMs),
      count: l.count,
      n: l.n,
    });
  });
}

async function storedWindow(uid: string): Promise<Timestamp> {
  let ts: Timestamp | undefined;
  await env.withSecurityRulesDisabled(async (ctx) => {
    ts = (await getDoc(doc(ctx.firestore(), `reportLimits/${uid}`))).get("windowStart") as Timestamp;
  });
  return ts!;
}

test("a guest files a report together with the limit doc", async () => {
  await assertSucceeds(file(guest("alice"), "alice", 1, firstLimit));
});

test("a report alone, or under another id, is refused", async () => {
  const f = guest("alice");
  await assertFails(setDoc(doc(f, "reports/alice_1"), report("alice")));
  await assertFails(file(f, "alice", 7, firstLimit));
  const b = writeBatch(f);
  b.set(doc(f, "reportLimits/alice"), firstLimit);
  b.set(doc(f, "reports/random-id"), report("alice"));
  await assertFails(b.commit());
});

test("one request cannot file two reports", async () => {
  const f = guest("alice");
  const b = writeBatch(f);
  b.set(doc(f, "reportLimits/alice"), firstLimit);
  b.set(doc(f, "reports/alice_1"), report("alice"));
  b.set(doc(f, "reports/alice_2"), report("alice"));
  await assertFails(b.commit());
});

test("the fields are checked", async () => {
  const f = guest("alice");
  for (const bad of [
    { reason: "spam" },
    { uid: "bob" },
    { status: "duzeltildi" },
    { note: "x".repeat(501) },
    { answer: "x".repeat(301) },
    { questionId: "" },
    { appVersion: "" },
    { correct: "no" },
    { extra: true },
    { createdAt: Timestamp.fromMillis(0) },
  ]) {
    await assertFails(file(f, "alice", 1, firstLimit, report("alice", bad)));
  }
  await assertSucceeds(
    file(f, "alice", 1, firstLimit, report("alice", { note: "I agree too da doğru", reason: "other_correct" })),
  );
});

test("the limit doc starts at one and belongs to its owner", async () => {
  const f = guest("alice");
  await assertFails(file(f, "alice", 1, { ...firstLimit, count: 0 }));
  await assertFails(file(f, "alice", 1, { ...firstLimit, n: 5 }));
  await assertFails(file(f, "alice", 1, { ...firstLimit, windowStart: Timestamp.fromMillis(0) }));
  await assertFails(setDoc(doc(f, "reportLimits/bob"), firstLimit));
});

test("a second report needs ten seconds", async () => {
  await seedLimit("alice", { windowAgoMs: 60_000, lastAgoMs: 3_000, count: 1, n: 1 });
  const window = await storedWindow("alice");
  const next = { windowStart: window, count: 2, last: serverTimestamp(), n: 2 };
  await assertFails(file(guest("alice"), "alice", 2, next));

  await seedLimit("alice", { windowAgoMs: 60_000, lastAgoMs: 30_000, count: 1, n: 1 });
  await assertSucceeds(file(guest("alice"), "alice", 2, { ...next, windowStart: await storedWindow("alice") }));
});

test("at most twenty a day, then a new window", async () => {
  await seedLimit("alice", { windowAgoMs: 3_600_000, lastAgoMs: 60_000, count: 20, n: 40 });
  const full = { windowStart: await storedWindow("alice"), count: 21, last: serverTimestamp(), n: 41 };
  await assertFails(file(guest("alice"), "alice", 41, full));
  // The counter must go up by exactly one, and the window may not be moved.
  await assertFails(file(guest("alice"), "alice", 41, { ...full, count: 20 }));
  await assertFails(file(guest("alice"), "alice", 41, { ...full, count: 1, windowStart: serverTimestamp() }));

  await seedLimit("alice", { windowAgoMs: 25 * 3_600_000, lastAgoMs: 60_000, count: 20, n: 40 });
  await assertSucceeds(
    file(guest("alice"), "alice", 41, { windowStart: serverTimestamp(), count: 1, last: serverTimestamp(), n: 41 }),
  );
});

test("an existing report cannot be filed over", async () => {
  await seedLimit("bob", { windowAgoMs: 60_000, lastAgoMs: 60_000, count: 1, n: 0 });
  // bob_1 exists: writing it again is an update, which only staff may do.
  const next = { windowStart: await storedWindow("bob"), count: 2, last: serverTimestamp(), n: 1 };
  await assertFails(file(guest("bob"), "bob", 1, next));
});

test("nobody but staff reads reports", async () => {
  await assertFails(getDoc(doc(guest("bob"), "reports/bob_1")));
  await assertFails(getDocs(collection(guest("bob"), "reports")));
  await assertFails(getDoc(doc(guest("alice"), "reports/bob_1")));
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), "reports/bob_1")));

  const staff = env.authenticatedContext("staff").firestore();
  await assertSucceeds(getDoc(doc(staff, "reports/bob_1")));
  await assertSucceeds(getDocs(collection(staff, "reports")));
  const claimed = env.authenticatedContext("boss", { isLingoraAdmin: true }).firestore();
  await assertSucceeds(getDocs(collection(claimed, "reports")));
});

test("staff set the status, and only the status", async () => {
  const staff = env.authenticatedContext("staff").firestore();
  const ref = doc(staff, "reports/bob_1");
  await assertSucceeds(updateDoc(ref, { status: "bakildi", statusAt: serverTimestamp(), statusBy: "staff" }));
  await assertSucceeds(updateDoc(ref, { status: "duzeltildi", statusAt: serverTimestamp(), statusBy: "staff" }));
  await assertFails(updateDoc(ref, { status: "silindi", statusAt: serverTimestamp(), statusBy: "staff" }));
  await assertFails(updateDoc(ref, { status: "yeni", statusAt: serverTimestamp(), statusBy: "someone" }));
  await assertFails(updateDoc(ref, { note: "edited", statusAt: serverTimestamp(), statusBy: "staff" }));
  await assertFails(deleteDoc(ref));

  const reporter = guest("bob");
  await assertFails(
    updateDoc(doc(reporter, "reports/bob_1"), { status: "bakildi", statusAt: serverTimestamp(), statusBy: "bob" }),
  );
  await assertFails(deleteDoc(doc(reporter, "reports/bob_1")));
});
