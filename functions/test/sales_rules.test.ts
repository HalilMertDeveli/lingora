// Rules for Kurumsal sales data: classes/{code}/speaking/{uid} (teacher
// speaking report), leads, leadRate and speakingStats (server-only).
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { after, before, beforeEach, test } from "node:test";

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { addDoc, collection, deleteDoc, doc, getDoc, getDocs, setDoc, setLogLevel } from "firebase/firestore";

import { emulatorHost, PROJECT_ID } from "./helpers.js";

let env: RulesTestEnvironment;
const CLASS = "SNFX8ABC";

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
    await setDoc(doc(f, `classes/${CLASS}`), { ownerUid: "ayse", name: "8-A", open: true });
    await setDoc(doc(f, `classes/${CLASS}/speaking/elif`), { conversations: 2, minutes: 7 });
    await setDoc(doc(f, `classes/${CLASS}/speaking/mert`), { conversations: 1, minutes: 2 });
    await setDoc(doc(f, "speakingStats/elif"), { conversations: 2 });
    await setDoc(doc(f, "leads/l1"), { org: "Başarı", phone: "05320000000" });
    await setDoc(doc(f, "leadRate/global"), { day: "2026-11-19", count: 1 });
  });
});

const db = (uid: string) =>
  env.authenticatedContext(uid, { firebase: { sign_in_provider: "google.com" } }).firestore();

test("the class teacher reads and lists speaking stats", async () => {
  await assertSucceeds(getDocs(collection(db("ayse"), `classes/${CLASS}/speaking`)));
  await assertSucceeds(getDoc(doc(db("ayse"), `classes/${CLASS}/speaking/elif`)));
});

test("a student reads only their own speaking stats", async () => {
  await assertSucceeds(getDoc(doc(db("elif"), `classes/${CLASS}/speaking/elif`)));
  await assertFails(getDoc(doc(db("elif"), `classes/${CLASS}/speaking/mert`)));
  await assertFails(getDocs(collection(db("elif"), `classes/${CLASS}/speaking`)));
});

test("other teachers and guests see nothing", async () => {
  await assertFails(getDocs(collection(db("veli"), `classes/${CLASS}/speaking`)));
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), `classes/${CLASS}/speaking/elif`)));
});

test("nobody writes speaking stats from the app", async () => {
  await assertFails(setDoc(doc(db("elif"), `classes/${CLASS}/speaking/elif`), { conversations: 99 }));
  await assertFails(setDoc(doc(db("ayse"), `classes/${CLASS}/speaking/elif`), { conversations: 0 }));
});

test("student and teacher may delete it (leaving, removing)", async () => {
  await assertSucceeds(deleteDoc(doc(db("elif"), `classes/${CLASS}/speaking/elif`)));
  await assertSucceeds(deleteDoc(doc(db("ayse"), `classes/${CLASS}/speaking/mert`)));
  await assertFails(deleteDoc(doc(db("veli"), `classes/${CLASS}/speaking/mert`)));
});

test("leads, lead counters and raw stats are server-only", async () => {
  const anyone = db("elif");
  await assertFails(getDoc(doc(anyone, "leads/l1")));
  await assertFails(getDocs(collection(anyone, "leads")));
  await assertFails(addDoc(collection(anyone, "leads"), { org: "Sahte" }));
  await assertFails(addDoc(collection(env.unauthenticatedContext().firestore(), "leads"), { org: "Sahte" }));
  await assertFails(getDoc(doc(anyone, "leadRate/global")));
  await assertFails(setDoc(doc(anyone, "leadRate/global"), { day: "2026-11-19", count: 0 }));
  await assertFails(getDoc(doc(anyone, "speakingStats/elif")));
  await assertFails(setDoc(doc(anyone, "speakingStats/elif"), { conversations: 50 }));
});
