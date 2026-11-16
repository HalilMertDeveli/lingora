// Profile rules (profiles/{uid}: chosen name and JPEG avatar) against the
// Firestore emulator. There is no Cloud Function: the rules are the server.
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { after, before, beforeEach, test } from "node:test";

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { Bytes, deleteDoc, doc, getDoc, serverTimestamp, setDoc, setLogLevel } from "firebase/firestore";

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
const guestDb = (uid: string) =>
  env.authenticatedContext(uid, { firebase: { sign_in_provider: "anonymous" } }).firestore();

/** A JPEG-looking blob of [size] bytes (starts with FF D8 FF). */
const jpeg = (size: number) => {
  const b = new Uint8Array(size);
  b.set([0xff, 0xd8, 0xff, 0xe0]);
  return Bytes.fromUint8Array(b);
};

const profile = (over: Record<string, unknown> = {}) => ({
  name: "Ali",
  photo: jpeg(20_000),
  clientUpdatedAt: 1,
  updatedAt: serverTimestamp(),
  ...over,
});

/** ali and zeynep are friends ("ali" < "zeynep", so the pair is ali_zeynep). */
async function makeFriends() {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "friendships/ali_zeynep"), { members: ["ali", "zeynep"] });
  });
}

test("the owner writes and reads their profile", async () => {
  await assertSucceeds(setDoc(doc(db("ali"), "profiles/ali"), profile()));
  const snap = await assertSucceeds(getDoc(doc(db("ali"), "profiles/ali")));
  if (snap.data()?.name !== "Ali") throw new Error("name not stored");
  // Removing the photo and the name.
  await assertSucceeds(setDoc(doc(db("ali"), "profiles/ali"), profile({ photo: null, name: null })));
  await assertSucceeds(deleteDoc(doc(db("ali"), "profiles/ali")));
});

test("nobody writes someone else's profile", async () => {
  await assertFails(setDoc(doc(db("zeynep"), "profiles/ali"), profile()));
  await makeFriends();
  await assertFails(setDoc(doc(db("zeynep"), "profiles/ali"), profile()));
  await assertSucceeds(setDoc(doc(db("ali"), "profiles/ali"), profile()));
  await assertFails(deleteDoc(doc(db("zeynep"), "profiles/ali")));
});

test("guests keep their photo on the device", async () => {
  await assertFails(setDoc(doc(guestDb("ali"), "profiles/ali"), profile()));
});

test("friends read the profile, strangers and guests do not", async () => {
  await assertSucceeds(setDoc(doc(db("ali"), "profiles/ali"), profile()));
  await assertFails(getDoc(doc(db("zeynep"), "profiles/ali")));
  await makeFriends();
  await assertSucceeds(getDoc(doc(db("zeynep"), "profiles/ali")));
  await assertFails(getDoc(doc(db("mert"), "profiles/ali")));
  await assertFails(getDoc(doc(guestDb("zeynep"), "profiles/ali")));
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), "profiles/ali")));
});

test("the photo is a JPEG of at most 60 KiB", async () => {
  const ref = doc(db("ali"), "profiles/ali");
  await assertSucceeds(setDoc(ref, profile({ photo: jpeg(61_440) })));
  await assertFails(setDoc(ref, profile({ photo: jpeg(61_441) })));
  await assertFails(setDoc(ref, profile({ photo: jpeg(50) })));
  // PNG signature, a string and a URL are refused.
  const png = new Uint8Array(1000);
  png.set([0x89, 0x50, 0x4e, 0x47]);
  await assertFails(setDoc(ref, profile({ photo: Bytes.fromUint8Array(png) })));
  await assertFails(setDoc(ref, profile({ photo: "data:image/jpeg;base64,/9j/" })));
  await assertFails(setDoc(ref, profile({ photo: "https://example.com/a.jpg" })));
});

test("the shape is checked", async () => {
  const ref = doc(db("ali"), "profiles/ali");
  await assertFails(setDoc(ref, profile({ name: "" })));
  await assertFails(setDoc(ref, profile({ name: "x".repeat(25) })));
  await assertSucceeds(setDoc(ref, profile({ name: "x".repeat(24) })));
  await assertFails(setDoc(ref, profile({ name: 42 })));
  await assertFails(setDoc(ref, profile({ email: "a@b.c" })));
  await assertFails(setDoc(ref, profile({ clientUpdatedAt: "dün" })));
  await assertFails(setDoc(ref, profile({ updatedAt: new Date(2020, 0, 1) })));
  const { updatedAt: _, ...noTime } = profile();
  await assertFails(setDoc(ref, noTime));
  // Only the name, without a photo.
  await assertSucceeds(setDoc(ref, { name: "Ali", updatedAt: serverTimestamp() }));
});
