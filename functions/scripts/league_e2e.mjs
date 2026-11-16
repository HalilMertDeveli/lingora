// End-to-end check of the Dünya Ligi against the Local Emulator Suite
// (auth + firestore + functions, project demo-lingora). Signs up real
// emulator accounts, calls the deployed callables over HTTP and reads the
// group through the security rules, like the app does.
//
//   npm run build
//   firebase emulators:exec --only auth,firestore,functions --project demo-lingora "node scripts/league_e2e.mjs"
//
// Ports come from the emulator environment variables (FIREBASE_AUTH_EMULATOR_HOST,
// FIRESTORE_EMULATOR_HOST) and FUNCTIONS_PORT (default 5001).
// With --seed EMAIL it also leaves a full group of 100 (rivals from several
// countries) around that account for screenshots; the password is "dilmac123".
import assert from "node:assert/strict";

const PROJECT = "demo-lingora";
const REGION = "europe-west1";
const AUTH = process.env.FIREBASE_AUTH_EMULATOR_HOST ?? "127.0.0.1:9099";
const STORE = process.env.FIRESTORE_EMULATOR_HOST ?? "127.0.0.1:8080";
const FUNCS = `127.0.0.1:${process.env.FUNCTIONS_PORT ?? "5001"}`;
const seedIdx = process.argv.indexOf("--seed");
const seedEmail = seedIdx > 0 ? process.argv[seedIdx + 1] : null;

async function json(res) {
  const text = await res.text();
  try {
    return { status: res.status, body: JSON.parse(text) };
  } catch {
    return { status: res.status, body: text };
  }
}

async function signUp(email) {
  const body = email ? { email, password: "dilmac123", returnSecureToken: true } : { returnSecureToken: true };
  const r = await json(
    await fetch(`http://${AUTH}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body),
    }),
  );
  assert.equal(r.status, 200, JSON.stringify(r.body));
  return { uid: r.body.localId, token: r.body.idToken };
}

async function call(user, name, data) {
  const r = await json(
    await fetch(`http://${FUNCS}/${PROJECT}/${REGION}/${name}`, {
      method: "POST",
      headers: { "content-type": "application/json", authorization: `Bearer ${user.token}` },
      body: JSON.stringify({ data }),
    }),
  );
  if (r.body?.error) return { error: r.body.error.status, message: r.body.error.message };
  return r.body.result;
}

const docs = `http://${STORE}/v1/projects/${PROJECT}/databases/(default)/documents`;

async function read(user, path) {
  return json(await fetch(`${docs}/${path}`, { headers: { authorization: `Bearer ${user.token}` } }));
}

async function write(user, path, fields) {
  return json(
    await fetch(`${docs}/${path}`, {
      method: "PATCH",
      headers: { "content-type": "application/json", authorization: `Bearer ${user.token}` },
      body: JSON.stringify({ fields }),
    }),
  );
}

const countries = ["TR", "DE", "AZ", "NL", "US", "GB", "FR", "AT", "KZ", "BE"];
const names = ["Ayşe", "Lena", "Eldar", "Sanne", "Emily", "Oliver", "Chloé", "Lukas", "Aruzhan", "Noah"];
const avatars = ["🦊", "🐼", "🐨", "🐯", "🦁", "🐸", "🦉", "🐙", "🦄", "🐢"];
let step = 0;
const ok = (msg) => console.log(`✔ ${++step}. ${msg}`);

// 1. A guest (anonymous) may not join.
const guest = await signUp(null);
assert.equal((await call(guest, "joinLeague", { name: "Misafir" })).error, "PERMISSION_DENIED");
ok("misafir (anonim) katılamaz");

// 2. Accounts from different countries land in the same Bronz group.
const ali = await signUp(`ali-${Date.now()}@dilmac.test`);
const lena = await signUp(`lena-${Date.now()}@dilmac.test`);
const seatA = await call(ali, "joinLeague", { name: "Ali", avatar: "🦊", country: "TR" });
const seatL = await call(lena, "joinLeague", { name: "Lena", avatar: "🐼", country: "DE" });
assert.equal(seatA.tier, 0);
assert.equal(seatA.groupId, seatL.groupId);
assert.deepEqual(await call(ali, "joinLeague", { name: "Ali", avatar: "🦊", country: "TR" }), seatA);
ok(`farklı ülkeler aynı gruba girer (${seatA.groupId}), katılım tekrar çağrılabilir`);

// 3. Bad input is refused.
assert.equal((await call(ali, "joinLeague", { country: "Türkiye" })).error, "INVALID_ARGUMENT");
assert.equal((await call(ali, "addLeagueXp", { weekXp: -5 })).error, "INVALID_ARGUMENT");
ok("geçersiz ülke ve XP reddedilir");

// 4. XP: the weekly total, capped per minute; a repeat never counts twice.
const r1 = await call(ali, "addLeagueXp", { weekXp: 120 });
assert.deepEqual(r1, { xp: 120, accepted: 120, pending: 0 });
await new Promise((r) => setTimeout(r, 2100));
const r2 = await call(ali, "addLeagueXp", { weekXp: 120 });
assert.equal(r2.accepted, 0);
await new Promise((r) => setTimeout(r, 2100));
const r3 = await call(ali, "addLeagueXp", { weekXp: 5000 });
assert.equal(r3.xp, 300); // 300 per minute
assert.equal(r3.pending, 4700);
ok("XP haftalık toplam olarak alınır, tekrar sayılmaz, dakikada 300 ile kırpılır");

// 5. Rules: members read the group, nobody writes rows; outsiders cannot read.
const list = await read(lena, `leagues/${seatA.groupId}/members`);
assert.equal(list.status, 200);
const rows = Object.fromEntries(list.body.documents.map((d) => [d.name.split("/").pop(), d.fields]));
assert.equal(rows[ali.uid].country.stringValue, "TR");
assert.equal(rows[ali.uid].xp.integerValue, "300");
assert.equal((await write(ali, `leagues/${seatA.groupId}/members/${ali.uid}`, { xp: { integerValue: 99999 } })).status, 403);
assert.equal((await write(ali, `leagues/${seatA.groupId}/members/${lena.uid}`, { xp: { integerValue: 0 } })).status, 403);
assert.equal((await write(ali, `leagueState/${ali.uid}`, { tier: { integerValue: 9 } })).status, 403);
assert.equal((await read(guest, `leagues/${seatA.groupId}/members`)).status, 403);
assert.equal((await read(ali, `leagueState/${ali.uid}`)).status, 200);
assert.equal((await read(ali, `leagueState/${lena.uid}`)).status, 403);
ok("kurallar: üyeler okur, kimse satır yazamaz, dışarıdaki okuyamaz");

// 6. Leaving removes the row; joining again brings it back.
assert.deepEqual(await call(lena, "leaveLeague", {}), { left: true });
assert.equal((await read(ali, `leagues/${seatA.groupId}/members/${lena.uid}`)).status, 404);
assert.equal((await call(lena, "addLeagueXp", { weekXp: 10 })).error, "FAILED_PRECONDITION");
await call(lena, "joinLeague", { name: "Lena", avatar: "🐼", country: "DE" });
assert.equal((await read(ali, `leagues/${seatA.groupId}/members/${lena.uid}`)).status, 200);
ok("ligden ayrılınca satır silinir, yeniden katılınca geri gelir");

if (seedEmail) {
  // A full group for screenshots: the seeded account in the middle.
  const me = await signUp(seedEmail);
  // Join first so the account shares the group the checks above opened.
  await call(me, "joinLeague", { name: "Mert", avatar: "⭐", country: "TR" });
  const others = [];
  for (let i = 0; i < 95; i++) {
    const u = await signUp(`rakip${i}-${Date.now()}@dilmac.test`);
    const c = countries[i % countries.length];
    await call(u, "joinLeague", { name: `${names[i % names.length]} ${String.fromCharCode(65 + (i % 26))}.`, avatar: avatars[i % avatars.length], country: c });
    others.push(u);
  }
  for (let i = 0; i < others.length; i++) {
    const xp = Math.max(0, Math.round(290 - i * 3 + ((i * 37) % 11)));
    if (xp > 0) await call(others[i], "addLeagueXp", { weekXp: xp });
  }
  await call(me, "addLeagueXp", { weekXp: 145 });
  const state = await read(me, `leagueState/${me.uid}`);
  console.log(`seed: ${seedEmail} -> ${state.body.fields.groupId.stringValue}`);
}
console.log(`\nDünya Ligi uçtan uca: ${step} adım geçti.`);
