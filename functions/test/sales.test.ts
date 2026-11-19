// Kurumsal sales: quote form endpoint, staff lead list, trial codes.
import assert from "node:assert/strict";
import { beforeEach, test } from "node:test";

import { Timestamp } from "firebase-admin/firestore";

import { Caller } from "../src/orgs.js";
import {
  createTrial,
  deleteLead,
  GLOBAL_DAILY,
  handleLeadRequest,
  LeadRequest,
  listLeads,
  parseLead,
  PER_IP_DAILY,
  trialEnd,
  updateLead,
} from "../src/sales.js";
import { adminDb, clearFirestore, rejectsWith } from "./helpers.js";

const db = adminDb();
const now = new Date("2026-11-19T09:00:00Z");
const staff: Caller = { uid: "staff", claims: { isLingoraAdmin: true } };
const stranger: Caller = { uid: "someone" };

beforeEach(clearFirestore);

const form = (over: Record<string, unknown> = {}) => ({
  org: "Başarı Dershanesi",
  name: "Ayşe Yılmaz",
  phone: "0532 000 00 00",
  email: "",
  students: "120",
  city: "Eskişehir",
  message: "LGS grubumuz için.\nPazartesi arayabilirsiniz.",
  consent: true,
  website: "",
  ...over,
});
const post = (body: unknown, over: Partial<LeadRequest> = {}): LeadRequest => ({
  method: "POST",
  origin: "https://dilbaz-3392e.web.app",
  ip: "203.0.113.5",
  body,
  ...over,
});

test("parseLead accepts a full form and normalizes it", () => {
  const r = parseLead(form({ email: " Ayse@Ornek.COM " }));
  assert.ok("lead" in r);
  assert.equal(r.lead.students, 120);
  assert.equal(r.lead.email, "ayse@ornek.com");
  assert.equal(r.lead.message, "LGS grubumuz için.\nPazartesi arayabilirsiniz.");
});

test("parseLead lists every bad field", () => {
  const r = parseLead({ org: "A", name: "", phone: "12", email: "x@", students: 0, city: "", consent: "true" });
  assert.ok("errors" in r);
  assert.deepEqual(r.errors.sort(), ["city", "consent", "email", "name", "org", "phone", "students"]);
  const none = parseLead(form({ phone: "", email: "" }));
  assert.ok("errors" in none && none.errors.includes("contact"));
});

test("a valid form becomes a lead with consent recorded", async () => {
  const out = await handleLeadRequest(db, post(form()), now);
  assert.deepEqual(out, { status: 200, body: { ok: true } });
  const leads = await db.collection("leads").get();
  assert.equal(leads.size, 1);
  const l = leads.docs[0].data();
  assert.equal(l.org, "Başarı Dershanesi");
  assert.equal(l.status, "yeni");
  assert.equal(l.consentVersion, "2026-11-19");
  assert.ok(l.consentAt instanceof Timestamp);
  assert.equal(l.website, undefined);
  // No raw IP anywhere.
  const rate = await db.collection("leadRate").get();
  for (const d of rate.docs) assert.ok(!JSON.stringify(d.data()).includes("203.0.113.5") && !d.id.includes("203"));
});

test("wrong method, foreign origin and bad input are refused", async () => {
  assert.equal((await handleLeadRequest(db, post(form(), { method: "GET" }), now)).status, 405);
  assert.equal((await handleLeadRequest(db, post(form(), { origin: "https://evil.example" }), now)).status, 403);
  const bad = await handleLeadRequest(db, post(form({ consent: false })), now);
  assert.equal(bad.status, 400);
  assert.deepEqual(bad.body.fields, ["consent"]);
  assert.equal((await db.collection("leads").get()).size, 0);
});

test("the honeypot pretends success but stores nothing", async () => {
  const out = await handleLeadRequest(db, post(form({ website: "http://spam" })), now);
  assert.equal(out.status, 200);
  assert.equal((await db.collection("leads").get()).size, 0);
});

test("rate limit per IP per day, then a new day", async () => {
  for (let i = 0; i < PER_IP_DAILY; i++) assert.equal((await handleLeadRequest(db, post(form()), now)).status, 200);
  assert.equal((await handleLeadRequest(db, post(form()), now)).status, 429);
  assert.equal((await handleLeadRequest(db, post(form(), { ip: "198.51.100.7" }), now)).status, 200);
  const tomorrow = new Date(now.getTime() + 24 * 3600e3);
  assert.equal((await handleLeadRequest(db, post(form()), tomorrow)).status, 200);
});

test("global daily cap", async () => {
  await db.doc("leadRate/global").set({ day: "2026-11-19", count: GLOBAL_DAILY });
  assert.equal((await handleLeadRequest(db, post(form()), now)).status, 429);
});

test("only staff list, update and delete leads", async () => {
  await handleLeadRequest(db, post(form()), now);
  await rejectsWith(listLeads(db, stranger, {}, now), "permission-denied");
  const { leads } = await listLeads(db, staff, {}, now);
  assert.equal(leads.length, 1);
  assert.equal(leads[0].city, "Eskişehir");
  const id = leads[0].id;
  await rejectsWith(updateLead(db, stranger, { id, status: "arandi" }, now), "permission-denied");
  await updateLead(db, staff, { id, status: "arandi", note: "Perşembe demo" }, now);
  await rejectsWith(updateLead(db, staff, { id, status: "uydurma" }, now), "invalid-argument");
  await rejectsWith(updateLead(db, staff, { id: "yok", status: "arandi" }, now), "not-found");
  assert.equal((await db.doc(`leads/${id}`).get()).get("note"), "Perşembe demo");
  await rejectsWith(deleteLead(db, stranger, { id }, now), "permission-denied");
  await deleteLead(db, staff, { id }, now);
  assert.equal((await db.collection("leads").get()).size, 0);
});

test("trial: N seat codes that end 30 days later and mark the lead", async () => {
  await handleLeadRequest(db, post(form()), now);
  const leadId = (await db.collection("leads").get()).docs[0].id;
  await rejectsWith(createTrial(db, stranger, { org: "X Okulu", students: 5, teachers: 1 }, now), "permission-denied");
  const t = await createTrial(db, staff, { org: "Başarı Dershanesi", students: 20, teachers: 1, leadId }, now);
  assert.equal(t.codes.length, 21);
  assert.equal(t.codes.filter((c) => c.role === "teacher").length, 1);
  assert.match(t.batch, /^deneme-basari-dershanesi-2026-11-19-\d{4}$/);
  assert.equal(new Date(t.expiresAt).toISOString(), "2026-12-19T20:59:59.000Z"); // 23:59:59 in Istanbul
  for (const c of t.codes) assert.match(c.code, /^[A-HJ-NP-Z2-9]{12}$/);
  const doc = (await db.doc(`licenseCodes/${t.codes[0].code}`).get()).data()!;
  assert.equal(doc.trial, true);
  assert.equal(doc.claimedBy, null);
  assert.equal(doc.org, "Başarı Dershanesi");
  assert.equal((doc.expiresAt as Timestamp).toMillis(), t.expiresAt);
  const lead = (await db.doc(`leads/${leadId}`).get()).data()!;
  assert.equal(lead.status, "deneme");
  assert.equal(lead.trialBatch, t.batch);
});

test("trial input limits", async () => {
  await rejectsWith(createTrial(db, staff, { org: "X", students: 5, teachers: 1 }, now), "invalid-argument");
  await rejectsWith(createTrial(db, staff, { org: "Okul", students: 61, teachers: 1 }, now), "invalid-argument");
  await rejectsWith(createTrial(db, staff, { org: "Okul", students: 5, teachers: 0 }, now), "invalid-argument");
  await rejectsWith(createTrial(db, staff, { org: "Okul", students: 5, teachers: 1, leadId: "yok" }, now), "not-found");
  assert.equal(trialEnd(new Date("2026-01-31T22:30:00Z")).toISOString(), "2026-03-03T20:59:59.000Z");
});
