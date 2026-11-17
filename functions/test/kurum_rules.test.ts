// Kurum lisansı ve sınıflar (licenseCodes, licenses, classes, members, classLinks)
// against the Firestore emulator. No Cloud Functions on the Spark plan: these
// rules are the whole server side (docs/kurumlar.md).
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
  query,
  serverTimestamp,
  setDoc,
  setLogLevel,
  Timestamp,
  updateDoc,
  where,
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
});

const db = (uid: string) =>
  env.authenticatedContext(uid, { firebase: { sign_in_provider: "google.com" } }).firestore();
type Db = ReturnType<typeof db>;
const guestDb = (uid: string) =>
  env.authenticatedContext(uid, { firebase: { sign_in_provider: "anonymous" } }).firestore();

const DAY = 86400e3;
const inDays = (n: number) => Timestamp.fromMillis(Date.now() + n * DAY);

const STUDENT_CODE = "STUD2345ABCD";
const STUDENT_CODE2 = "STUD2345WXYZ";
const TEACHER_CODE = "TEAC2345ABCD";
const OLD_CODE = "EXPR2345ABCD";
const CLASS = "SNFX8ABC";

/** Seat codes as the operator's script writes them (rules off). */
async function seedCodes() {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const f = ctx.firestore();
    const base = { org: "Deneme Ortaokulu", batch: "2026-11", claimedBy: null, claimedAt: null };
    await setDoc(doc(f, `licenseCodes/${STUDENT_CODE}`), { ...base, role: "student", expiresAt: inDays(200) });
    await setDoc(doc(f, `licenseCodes/${STUDENT_CODE2}`), { ...base, role: "student", expiresAt: inDays(200) });
    await setDoc(doc(f, `licenseCodes/${TEACHER_CODE}`), { ...base, role: "teacher", expiresAt: inDays(200) });
    await setDoc(doc(f, `licenseCodes/${OLD_CODE}`), { ...base, role: "student", expiresAt: inDays(-1) });
  });
}

/** What the app writes in one batch: claim the code and copy it into licenses/{uid}. */
function claim(f: Db, uid: string, code: string, role = "student", expiresAt = inDays(200), over = {}) {
  const b = writeBatch(f);
  b.update(doc(f, `licenseCodes/${code}`), { claimedBy: uid, claimedAt: serverTimestamp() });
  b.set(doc(f, `licenses/${uid}`), {
    code,
    org: "Deneme Ortaokulu",
    role,
    expiresAt,
    claimedAt: serverTimestamp(),
    ...over,
  });
  return b.commit();
}

/** The exact end date stored on a seed code (the license must copy it). */
async function codeExpiry(code: string): Promise<Timestamp> {
  let t: Timestamp | undefined;
  await env.withSecurityRulesDisabled(async (ctx) => {
    t = (await getDoc(doc(ctx.firestore(), `licenseCodes/${code}`))).get("expiresAt") as Timestamp;
  });
  return t!;
}

async function claimOk(f: Db, uid: string, code: string, role = "student") {
  await assertSucceeds(claim(f, uid, code, role, await codeExpiry(code)));
}

const newClass = (owner: string, over: Record<string, unknown> = {}) => ({
  ownerUid: owner,
  name: "8-A İngilizce",
  teacherName: "Ayşe Öğretmen",
  org: "Deneme Ortaokulu",
  open: true,
  createdAt: serverTimestamp(),
  ...over,
});

const member = (over: Record<string, unknown> = {}) => ({
  name: "Elif",
  streak: 3,
  lessonsDone: 12,
  unitsDone: 2,
  weekXp: 140,
  week: "2026-11-16",
  topErrors: ["article", "tense"],
  joinedAt: serverTimestamp(),
  updatedAt: serverTimestamp(),
  ...over,
});

async function teacherWithClass() {
  await seedCodes();
  await claimOk(db("ayse"), "ayse", TEACHER_CODE, "teacher");
  await assertSucceeds(setDoc(doc(db("ayse"), `classes/${CLASS}`), newClass("ayse")));
}

// ---- licenses ----

test("license codes cannot be listed, created or deleted by apps", async () => {
  await seedCodes();
  await assertSucceeds(getDoc(doc(db("elif"), `licenseCodes/${STUDENT_CODE}`)));
  await assertFails(getDoc(doc(guestDb("g"), `licenseCodes/${STUDENT_CODE}`)));
  await assertFails(getDocs(collection(db("elif"), "licenseCodes")));
  await assertFails(
    setDoc(doc(db("elif"), "licenseCodes/NEWX2345ABCD"), {
      org: "X",
      role: "teacher",
      expiresAt: inDays(999),
      batch: "x",
      claimedBy: null,
      claimedAt: null,
    }),
  );
  await assertFails(deleteDoc(doc(db("elif"), `licenseCodes/${STUDENT_CODE}`)));
});

test("a student claims a seat and gets the code's org, role and end date", async () => {
  await seedCodes();
  await claimOk(db("elif"), "elif", STUDENT_CODE);
  await assertSucceeds(getDoc(doc(db("elif"), "licenses/elif")));
  await assertFails(getDoc(doc(db("mert"), "licenses/elif")));
});

test("forged licenses are refused", async () => {
  await seedCodes();
  const exp = await codeExpiry(STUDENT_CODE);
  // A teacher role, a later end date or another org than the code says.
  await assertFails(claim(db("elif"), "elif", STUDENT_CODE, "teacher", exp));
  await assertFails(claim(db("elif"), "elif", STUDENT_CODE, "student", inDays(999)));
  await assertFails(claim(db("elif"), "elif", STUDENT_CODE, "student", exp, { org: "Başka" }));
  await assertFails(claim(db("elif"), "elif", STUDENT_CODE, "student", exp, { extra: 1 }));
  // A license without claiming the code, or claiming it for someone else.
  await assertFails(
    setDoc(doc(db("elif"), "licenses/elif"), {
      code: STUDENT_CODE,
      org: "Deneme Ortaokulu",
      role: "student",
      expiresAt: exp,
      claimedAt: serverTimestamp(),
    }),
  );
  await assertFails(updateDoc(doc(db("elif"), `licenseCodes/${STUDENT_CODE}`), { claimedBy: "elif", claimedAt: serverTimestamp() }));
  await assertFails(claim(db("elif"), "mert", STUDENT_CODE, "student", exp));
  // Guests cannot claim: the seat would be lost with the phone.
  await assertFails(claim(guestDb("g"), "g", STUDENT_CODE, "student", exp));
});

test("a seat is single-use and expired codes cannot be claimed", async () => {
  await seedCodes();
  await claimOk(db("elif"), "elif", STUDENT_CODE);
  await assertFails(claim(db("mert"), "mert", STUDENT_CODE, "student", await codeExpiry(STUDENT_CODE)));
  await assertFails(claim(db("mert"), "mert", OLD_CODE, "student", await codeExpiry(OLD_CODE)));
});

test("one active license per user: no burning a second seat", async () => {
  await seedCodes();
  await claimOk(db("elif"), "elif", STUDENT_CODE);
  await assertFails(claim(db("elif"), "elif", STUDENT_CODE2, "student", await codeExpiry(STUDENT_CODE2)));
  // Active licenses cannot be deleted either (then claimed again).
  await assertFails(deleteDoc(doc(db("elif"), "licenses/elif")));
});

test("re-linking a seat already claimed by the same user (second phone)", async () => {
  await seedCodes();
  await claimOk(db("elif"), "elif", STUDENT_CODE);
  await assertSucceeds(
    setDoc(doc(db("elif"), "licenses/elif"), {
      code: STUDENT_CODE,
      org: "Deneme Ortaokulu",
      role: "student",
      expiresAt: await codeExpiry(STUDENT_CODE),
      claimedAt: serverTimestamp(),
    }),
  );
});

test("after a license expires the user may claim a new seat", async () => {
  await seedCodes();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const f = ctx.firestore();
    await updateDoc(doc(f, `licenseCodes/${OLD_CODE}`), { claimedBy: "elif", claimedAt: new Date() });
    await setDoc(doc(f, "licenses/elif"), {
      code: OLD_CODE,
      org: "Deneme Ortaokulu",
      role: "student",
      expiresAt: inDays(-1),
      claimedAt: new Date(),
    });
  });
  await claimOk(db("elif"), "elif", STUDENT_CODE2);
});

// ---- classes ----

test("only a teacher with an active seat opens a class", async () => {
  await seedCodes();
  await assertFails(setDoc(doc(db("ayse"), `classes/${CLASS}`), newClass("ayse")));
  await claimOk(db("elif"), "elif", STUDENT_CODE);
  await assertFails(setDoc(doc(db("elif"), `classes/${CLASS}`), newClass("elif")));
  await claimOk(db("ayse"), "ayse", TEACHER_CODE, "teacher");
  // Bad code, someone else as owner, other org, extra field.
  await assertFails(setDoc(doc(db("ayse"), "classes/snfx8abc"), newClass("ayse")));
  await assertFails(setDoc(doc(db("ayse"), `classes/${CLASS}`), newClass("mert")));
  await assertFails(setDoc(doc(db("ayse"), `classes/${CLASS}`), newClass("ayse", { org: "Başka" })));
  await assertFails(setDoc(doc(db("ayse"), `classes/${CLASS}`), newClass("ayse", { email: "x" })));
  await assertSucceeds(setDoc(doc(db("ayse"), `classes/${CLASS}`), newClass("ayse")));
  // Taking over an existing class is an update by a non-owner.
  await assertFails(setDoc(doc(db("mert"), `classes/${CLASS}`), newClass("mert")));
});

test("a revoked teacher seat cannot open classes", async () => {
  await seedCodes();
  await claimOk(db("ayse"), "ayse", TEACHER_CODE, "teacher");
  await env.withSecurityRulesDisabled(async (ctx) => {
    await updateDoc(doc(ctx.firestore(), `licenseCodes/${TEACHER_CODE}`), { claimedBy: "revoked" });
  });
  await assertFails(setDoc(doc(db("ayse"), `classes/${CLASS}`), newClass("ayse")));
});

test("class: anyone signed in looks it up by code, only the owner lists and edits", async () => {
  await teacherWithClass();
  await assertSucceeds(getDoc(doc(guestDb("g"), `classes/${CLASS}`)));
  await assertSucceeds(getDocs(query(collection(db("ayse"), "classes"), where("ownerUid", "==", "ayse"))));
  await assertFails(getDocs(collection(db("mert"), "classes")));
  await assertFails(getDocs(query(collection(db("mert"), "classes"), where("ownerUid", "==", "ayse"))));
  await assertSucceeds(updateDoc(doc(db("ayse"), `classes/${CLASS}`), { open: false }));
  await assertFails(updateDoc(doc(db("ayse"), `classes/${CLASS}`), { ownerUid: "mert" }));
  await assertFails(updateDoc(doc(db("mert"), `classes/${CLASS}`), { open: true }));
  await assertFails(deleteDoc(doc(db("mert"), `classes/${CLASS}`)));
  await assertSucceeds(deleteDoc(doc(db("ayse"), `classes/${CLASS}`)));
});

// ---- members ----

const memberRef = (f: Db, uid: string) => doc(f, `classes/${CLASS}/members/${uid}`);

test("a student (also a guest) joins an open class with a learning summary only", async () => {
  await teacherWithClass();
  await assertSucceeds(setDoc(memberRef(db("elif"), "elif"), member()));
  await assertSucceeds(setDoc(memberRef(guestDb("g"), "g"), member({ name: "Can" })));
  // As someone else, with contact data, bad numbers or too many errors.
  await assertFails(setDoc(memberRef(db("mert"), "elif2"), member()));
  await assertFails(setDoc(memberRef(db("mert"), "mert"), member({ email: "m@example.com" })));
  await assertFails(setDoc(memberRef(db("mert"), "mert"), member({ phone: "5550000000" })));
  await assertFails(setDoc(memberRef(db("mert"), "mert"), member({ streak: -1 })));
  await assertFails(setDoc(memberRef(db("mert"), "mert"), member({ weekXp: 1.5 })));
  await assertFails(setDoc(memberRef(db("mert"), "mert"), member({ topErrors: ["a", "b", "c", "d"] })));
  await assertFails(setDoc(memberRef(db("mert"), "mert"), member({ topErrors: ["bad name!"] })));
  await assertFails(setDoc(memberRef(db("mert"), "mert"), member({ name: "" })));
  await assertFails(setDoc(memberRef(db("mert"), "mert"), member({ week: "dün" })));
  // A class that does not exist.
  await assertFails(setDoc(doc(db("mert"), "classes/YOKX2345/members/mert"), member()));
});

test("a closed class takes no new students, but members keep reporting", async () => {
  await teacherWithClass();
  await assertSucceeds(setDoc(memberRef(db("elif"), "elif"), member()));
  await assertSucceeds(updateDoc(doc(db("ayse"), `classes/${CLASS}`), { open: false }));
  await assertFails(setDoc(memberRef(db("mert"), "mert"), member()));
  await assertSucceeds(updateDoc(memberRef(db("elif"), "elif"), { streak: 4, updatedAt: serverTimestamp() }));
  // joinedAt cannot be rewritten.
  await assertFails(updateDoc(memberRef(db("elif"), "elif"), { joinedAt: Timestamp.fromMillis(0), updatedAt: serverTimestamp() }));
});

test("only the teacher and the student see a summary", async () => {
  await teacherWithClass();
  await assertSucceeds(setDoc(memberRef(db("elif"), "elif"), member()));
  await assertSucceeds(setDoc(memberRef(db("mert"), "mert"), member({ name: "Mert" })));
  await assertSucceeds(getDocs(collection(db("ayse"), `classes/${CLASS}/members`)));
  await assertSucceeds(getDoc(memberRef(db("elif"), "elif")));
  await assertFails(getDoc(memberRef(db("elif"), "mert")));
  await assertFails(getDocs(collection(db("elif"), `classes/${CLASS}/members`)));
  // Another teacher with a seat of their own sees nothing either.
  await claimOk(db("zeki"), "zeki", STUDENT_CODE2);
  await assertFails(getDocs(collection(db("zeki"), `classes/${CLASS}/members`)));
  // The teacher cannot write a student's numbers.
  await assertFails(updateDoc(memberRef(db("ayse"), "elif"), { streak: 99, updatedAt: serverTimestamp() }));
});

test("the teacher removes a student; the student may leave", async () => {
  await teacherWithClass();
  await assertSucceeds(setDoc(memberRef(db("elif"), "elif"), member()));
  await assertSucceeds(setDoc(memberRef(db("mert"), "mert"), member({ name: "Mert" })));
  await assertFails(deleteDoc(memberRef(db("elif"), "mert")));
  await assertSucceeds(deleteDoc(memberRef(db("ayse"), "mert")));
  await assertSucceeds(deleteDoc(memberRef(db("elif"), "elif")));
  // After removal, reporting does not bring the student back.
  await assertFails(updateDoc(memberRef(db("mert"), "mert"), { streak: 5, updatedAt: serverTimestamp() }));
});

// ---- classLinks ----

test("classLinks: own doc only, at most five classes", async () => {
  const ref = (f: Db, uid: string) => doc(f, `classLinks/${uid}`);
  await assertSucceeds(setDoc(ref(db("elif"), "elif"), { codes: [CLASS], updatedAt: serverTimestamp() }));
  await assertSucceeds(getDoc(ref(db("elif"), "elif")));
  await assertFails(getDoc(ref(db("mert"), "elif")));
  await assertFails(setDoc(ref(db("mert"), "elif"), { codes: [], updatedAt: serverTimestamp() }));
  await assertFails(
    setDoc(ref(db("elif"), "elif"), { codes: ["A", "B", "C", "D", "E", "F"], updatedAt: serverTimestamp() }),
  );
  await assertFails(setDoc(ref(db("elif"), "elif"), { codes: [], updatedAt: serverTimestamp(), x: 1 }));
});
