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

// ---- Mağaza showcase (lib/services/showcase.dart) ----

const showcase = (over: Record<string, unknown> = {}) => ({
  avatar: "av_tilki",
  frame: "fr_altin",
  items: ["mx_tac", "th_iznik", "av_lale"],
  ...over,
});

test("the owner writes a showcase next to the profile (merge) and friends read it", async () => {
  await assertSucceeds(setDoc(doc(db("ali"), "profiles/ali"), profile()));
  await assertSucceeds(
    setDoc(doc(db("ali"), "profiles/ali"), { showcase: showcase(), updatedAt: serverTimestamp() }, { merge: true }),
  );
  // A later profile write (merge) keeps it.
  await assertSucceeds(setDoc(doc(db("ali"), "profiles/ali"), profile({ name: "Ali K" }), { merge: true }));
  await makeFriends();
  const snap = await assertSucceeds(getDoc(doc(db("zeynep"), "profiles/ali")));
  const s = snap.data()?.showcase;
  if (s?.avatar !== "av_tilki" || s?.items?.length !== 3) throw new Error("showcase not stored");
  // Empty showcase.
  await assertSucceeds(
    setDoc(
      doc(db("ali"), "profiles/ali"),
      { showcase: showcase({ avatar: null, frame: null, items: [] }), updatedAt: serverTimestamp() },
      { merge: true },
    ),
  );
});

test("a showcase alone creates the profile document", async () => {
  await assertSucceeds(setDoc(doc(db("ali"), "profiles/ali"), { showcase: showcase(), updatedAt: serverTimestamp() }));
});

test("strangers and guests cannot read or write a showcase", async () => {
  await assertSucceeds(setDoc(doc(db("ali"), "profiles/ali"), { showcase: showcase(), updatedAt: serverTimestamp() }));
  await assertFails(getDoc(doc(db("zeynep"), "profiles/ali")));
  await assertFails(
    setDoc(doc(db("zeynep"), "profiles/ali"), { showcase: showcase(), updatedAt: serverTimestamp() }, { merge: true }),
  );
  await assertFails(
    setDoc(doc(guestDb("misafir"), "profiles/misafir"), { showcase: showcase(), updatedAt: serverTimestamp() }),
  );
});

test("a malformed showcase is refused", async () => {
  const bad: unknown[] = [
    showcase({ items: ["av_a", "av_b", "av_c", "av_d"] }), // more than 3
    showcase({ items: ["<script>"] }), // not an item id
    showcase({ items: ["xx_tilki"] }), // unknown category
    showcase({ avatar: "fr_altin" }), // a frame as the avatar
    showcase({ frame: "av_tilki" }), // an avatar as the frame
    showcase({ avatar: "av_" + "x".repeat(30) }), // too long
    showcase({ items: "mx_tac" }), // not a list
    { ...showcase(), extra: true }, // unknown key
    { avatar: "av_tilki", frame: null }, // items missing
    "av_tilki", // not a map
  ];
  for (const s of bad) {
    await assertFails(setDoc(doc(db("ali"), "profiles/ali"), { showcase: s, updatedAt: serverTimestamp() }));
  }
  // updatedAt must still be the server time.
  await assertFails(setDoc(doc(db("ali"), "profiles/ali"), { showcase: showcase(), updatedAt: 5 }));
});

test("the showcase can say avatar-instead-of-photo and hold Pofuduk outfits", async () => {
  await assertSucceeds(
    setDoc(doc(db("ali"), "profiles/ali"), {
      showcase: showcase({ useAvatar: true, items: ["px_tac", "fr_gokkusagi"] }),
      updatedAt: serverTimestamp(),
    }),
  );
  await makeFriends();
  const snap = await assertSucceeds(getDoc(doc(db("zeynep"), "profiles/ali")));
  if (snap.data()?.showcase?.useAvatar !== true) throw new Error("useAvatar not stored");
  await assertFails(
    setDoc(doc(db("ali"), "profiles/ali"), {
      showcase: showcase({ useAvatar: "yes" }),
      updatedAt: serverTimestamp(),
    }),
  );
});

test("the showcase holds the worn theme and mascot outfits, and friends read them", async () => {
  await assertSucceeds(
    setDoc(doc(db("ali"), "profiles/ali"), {
      showcase: showcase({ theme: "th_iznik", mascot: "mx_tac", pofuduk: "px_kep" }),
      updatedAt: serverTimestamp(),
    }),
  );
  await makeFriends();
  const snap = await assertSucceeds(getDoc(doc(db("zeynep"), "profiles/ali")));
  const s = snap.data()?.showcase;
  if (s?.theme !== "th_iznik" || s?.mascot !== "mx_tac" || s?.pofuduk !== "px_kep") {
    throw new Error("worn items not stored");
  }
  // The worn slots may be cleared.
  await assertSucceeds(
    setDoc(doc(db("ali"), "profiles/ali"), {
      showcase: showcase({ theme: null, mascot: null, pofuduk: null }),
      updatedAt: serverTimestamp(),
    }),
  );
});

test("only known catalog ids are accepted, each in its own slot", async () => {
  const bad: unknown[] = [
    showcase({ avatar: "av_bilinmeyen" }), // matches the id shape, not in the catalog
    showcase({ frame: "fr_yok" }),
    showcase({ items: ["th_yok"] }),
    showcase({ items: ["mx_tac", "av_bilinmeyen"] }),
    showcase({ theme: "th_yok" }),
    showcase({ mascot: "mx_yok" }),
    showcase({ pofuduk: "px_yok" }),
    showcase({ theme: "av_kedi" }), // a known avatar as the theme
    showcase({ mascot: "px_kep" }), // a Pofuduk outfit on Dilbaz
    showcase({ pofuduk: "mx_tac" }), // a Dilbaz outfit on Pofuduk
    showcase({ theme: 42 }),
  ];
  for (const s of bad) {
    await assertFails(setDoc(doc(db("ali"), "profiles/ali"), { showcase: s, updatedAt: serverTimestamp() }));
  }
});
