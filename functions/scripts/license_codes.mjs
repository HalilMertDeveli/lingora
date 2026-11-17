// Kurum lisans kodları: the operator's tool for selling seats to schools and
// companies (docs/kurumlar.md). Runs on the operator's computer with the
// Admin SDK, so it works on the Spark plan (no Cloud Functions).
//
//   # Emulator (safe to try):
//   firebase emulators:exec --only firestore --project demo-lingora \
//     "node scripts/license_codes.mjs create --org \"Deneme Ortaokulu\" --seats 30 --until 2027-06-30 --out kodlar.csv"
//
//   # Real project: a service account key of the project (never commit it):
//   GOOGLE_APPLICATION_CREDENTIALS=~/keys/dilbaz-admin.json \
//     node scripts/license_codes.mjs create --project <id> --org "..." --seats 30 --teachers 2 --until 2027-06-30 --out kodlar.csv
//
// Commands
//   create  --org NAME --seats N [--teachers T] --until YYYY-MM-DD [--batch ID] [--out FILE.csv]
//           N student seats + T teacher seats, valid until the end of that day (Turkey time).
//   status  --batch ID                    how many seats of a batch are used
//   release --code CODE                   frees a seat (the holder loses Premium); it can be given again
//   extend  --batch ID --until YYYY-MM-DD  renewal: new end date for the whole batch and its holders
//
// Without --project it refuses to run unless FIRESTORE_EMULATOR_HOST is set.
import { randomInt } from "node:crypto";
import { writeFileSync } from "node:fs";

import { initializeApp } from "firebase-admin/app";
import { getFirestore, Timestamp } from "firebase-admin/firestore";

const ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // [A-HJ-NP-Z2-9] in firestore.rules
const CODE_LENGTH = 12;

function arg(name, fallback) {
  const i = process.argv.indexOf(`--${name}`);
  return i > 0 ? process.argv[i + 1] : fallback;
}

function fail(msg) {
  console.error(msg);
  process.exit(1);
}

const command = process.argv[2];
const project = arg("project", process.env.FIRESTORE_EMULATOR_HOST ? "demo-lingora" : undefined);
if (!project) fail("--project vermediniz ve FIRESTORE_EMULATOR_HOST yok: yanlışlıkla gerçek projeye yazmamak için durdum.");
initializeApp({ projectId: project });
const db = getFirestore();

const newCode = () => Array.from({ length: CODE_LENGTH }, () => ALPHABET[randomInt(ALPHABET.length)]).join("");
const pretty = (c) => `${c.slice(0, 4)}-${c.slice(4, 8)}-${c.slice(8)}`;

/** End of the given day in Turkey (UTC+3). */
function endOfDay(day) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(day ?? "")) fail("--until YYYY-AA-GG biçiminde olmalı.");
  const ms = Date.parse(`${day}T23:59:59+03:00`);
  if (Number.isNaN(ms) || ms < Date.now()) fail("--until geçerli ve gelecekte bir gün olmalı.");
  return Timestamp.fromMillis(ms);
}

async function create() {
  const org = arg("org");
  if (!org || org.length > 60) fail("--org gerekli (en fazla 60 karakter).");
  const seats = Number(arg("seats", "0"));
  const teachers = Number(arg("teachers", "0"));
  if (!Number.isInteger(seats) || !Number.isInteger(teachers) || seats < 0 || teachers < 0 || seats + teachers < 1) {
    fail("--seats ve --teachers sıfır ya da pozitif tam sayı olmalı (toplam en az 1).");
  }
  const expiresAt = endOfDay(arg("until"));
  const batchId = arg("batch", `${org.toLowerCase().replace(/[^a-z0-9]+/g, "-")}-${new Date().toISOString().slice(0, 10)}`);
  const rows = [];
  const roles = [...Array(teachers).fill("teacher"), ...Array(seats).fill("student")];
  for (let i = 0; i < roles.length; i += 400) {
    const batch = db.batch();
    for (const role of roles.slice(i, i + 400)) {
      let code;
      do code = newCode();
      while ((await db.doc(`licenseCodes/${code}`).get()).exists);
      batch.create(db.doc(`licenseCodes/${code}`), {
        org,
        role,
        expiresAt,
        batch: batchId,
        claimedBy: null,
        claimedAt: null,
      });
      rows.push([pretty(code), role === "teacher" ? "Öğretmen" : "Öğrenci"]);
    }
    await batch.commit();
  }
  const csv = ["Kod;Rol;Kurum;Bitiş", ...rows.map(([c, r]) => `${c};${r};${org};${arg("until")}`)].join("\n");
  const out = arg("out");
  if (out) writeFileSync(out, "﻿" + csv + "\n", "utf8");
  console.log(`${rows.length} kod oluşturuldu (parti: ${batchId}).${out ? ` CSV: ${out}` : ""}`);
  if (!out) console.log(csv);
}

async function status() {
  const batchId = arg("batch");
  if (!batchId) fail("--batch gerekli.");
  const snap = await db.collection("licenseCodes").where("batch", "==", batchId).get();
  const used = snap.docs.filter((d) => d.get("claimedBy")).length;
  console.log(`${batchId}: ${snap.size} koltuk, ${used} kullanılmış, ${snap.size - used} boş.`);
}

async function release() {
  const code = (arg("code") ?? "").toUpperCase().replace(/[\s-]/g, "");
  const ref = db.doc(`licenseCodes/${code}`);
  const snap = await ref.get();
  if (!snap.exists) fail("Kod bulunamadı.");
  const holder = snap.get("claimedBy");
  const batch = db.batch();
  batch.update(ref, { claimedBy: null, claimedAt: null });
  if (holder) {
    const lic = await db.doc(`licenses/${holder}`).get();
    if (lic.exists && lic.get("code") === code) batch.delete(lic.ref);
  }
  await batch.commit();
  console.log(holder ? `Koltuk boşaltıldı (önceki kullanıcı: ${holder}).` : "Kod zaten boştu.");
}

async function extend() {
  const batchId = arg("batch");
  if (!batchId) fail("--batch gerekli.");
  const expiresAt = endOfDay(arg("until"));
  const snap = await db.collection("licenseCodes").where("batch", "==", batchId).get();
  let licenses = 0;
  for (let i = 0; i < snap.docs.length; i += 200) {
    const batch = db.batch();
    for (const d of snap.docs.slice(i, i + 200)) {
      batch.update(d.ref, { expiresAt });
      const holder = d.get("claimedBy");
      if (holder) {
        const lic = await db.doc(`licenses/${holder}`).get();
        if (lic.exists && lic.get("code") === d.id) {
          batch.update(lic.ref, { expiresAt });
          licenses++;
        }
      }
    }
    await batch.commit();
  }
  console.log(`${snap.size} kod ve ${licenses} etkin lisans ${arg("until")} tarihine uzatıldı.`);
}

const commands = { create, status, release, extend };
if (!commands[command]) fail("Komut: create | status | release | extend (ayrıntı dosyanın başında).");
await commands[command]();
