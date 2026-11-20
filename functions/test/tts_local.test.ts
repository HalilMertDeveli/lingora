import { strict as assert } from "node:assert";
import { test } from "node:test";

import { localGcloudTts, localTtsQuotaProject } from "../src/tts.js";

test("local TTS quota project only inside the emulator with an explicit opt-in", () => {
  assert.equal(localTtsQuotaProject({}), undefined);
  assert.equal(localTtsQuotaProject({ LINGORA_TTS_QUOTA_PROJECT: "p" }), undefined); // production
  assert.equal(localTtsQuotaProject({ FUNCTIONS_EMULATOR: "true" }), undefined);
  assert.equal(localTtsQuotaProject({ FUNCTIONS_EMULATOR: "true", LINGORA_TTS_QUOTA_PROJECT: "  " }), undefined);
  assert.equal(localTtsQuotaProject({ FUNCTIONS_EMULATOR: "true", LINGORA_TTS_QUOTA_PROJECT: "p1" }), "p1");
});

test("local gcloud TTS sends the quota project and reuses the token", async () => {
  let tokens = 0;
  const calls: { headers: Record<string, string>; body: string }[] = [];
  let now = 0;
  const fakeFetch = (async (_url: string, init: RequestInit) => {
    calls.push({ headers: init.headers as Record<string, string>, body: String(init.body) });
    return new Response(JSON.stringify({ audioContent: Buffer.from("mp3").toString("base64") }), { status: 200 });
  }) as unknown as typeof fetch;
  const client = localGcloudTts(
    "quota-1",
    async () => `t${++tokens}`,
    fakeFetch,
    () => now,
  );
  const req = { text: "Hi", voiceName: "en-US-Chirp3-HD-Aoede", languageCode: "en-US", rate: 0.85 };
  assert.equal((await client.synthesize(req)).toString(), "mp3");
  await client.synthesize(req);
  assert.equal(tokens, 1);
  now = 46 * 60_000;
  await client.synthesize(req);
  assert.equal(tokens, 2);
  assert.equal(calls[0].headers["x-goog-user-project"], "quota-1");
  assert.equal(calls[0].headers.Authorization, "Bearer t1");
  assert.equal(JSON.parse(calls[0].body).audioConfig.speakingRate, 0.85);
});

test("local gcloud TTS asks gcloud once for parallel sentences, and again after a failure", async () => {
  let calls = 0;
  let fail = true;
  const fakeFetch = (async () =>
    new Response(JSON.stringify({ audioContent: "AA==" }), { status: 200 })) as unknown as typeof fetch;
  const client = localGcloudTts(
    "q",
    async () => {
      calls++;
      await new Promise((r) => setTimeout(r, 10));
      if (fail) throw new Error("gcloud slow");
      return "t";
    },
    fakeFetch,
  );
  const req = { text: "Hi", voiceName: "v", languageCode: "en-US", rate: 1 };
  const first = await Promise.allSettled([client.synthesize(req), client.synthesize(req), client.synthesize(req)]);
  assert.equal(calls, 1);
  assert.ok(first.every((r) => r.status === "rejected"));
  fail = false;
  await Promise.all([client.synthesize(req), client.synthesize(req)]);
  assert.equal(calls, 2);
});

test("local gcloud TTS turns HTTP errors into a thrown error (app falls back)", async () => {
  const fakeFetch = (async () => new Response("no", { status: 403 })) as unknown as typeof fetch;
  const client = localGcloudTts("q", async () => "t", fakeFetch);
  await assert.rejects(
    client.synthesize({ text: "Hi", voiceName: "v", languageCode: "en-US", rate: 1 }),
    /http 403/,
  );
});
