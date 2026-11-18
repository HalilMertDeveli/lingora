import { test } from "node:test";
import assert from "node:assert/strict";
import Anthropic from "@anthropic-ai/sdk";

import { pickMode, sampleFromSchema, stubClaude, stubClaudeEnabled } from "../src/ai_stub.js";

test("stub is off unless both the emulator flag and the opt-in are set", () => {
  assert.equal(stubClaudeEnabled({}), false);
  assert.equal(stubClaudeEnabled({ LINGORA_AI_STUB: "1" }), false); // production never sets FUNCTIONS_EMULATOR
  assert.equal(stubClaudeEnabled({ FUNCTIONS_EMULATOR: "true" }), false);
  assert.equal(stubClaudeEnabled({ FUNCTIONS_EMULATOR: "false", LINGORA_AI_STUB: "1" }), false);
  assert.equal(stubClaudeEnabled({ FUNCTIONS_EMULATOR: "true", LINGORA_AI_STUB: "1" }), true);
});

test("sampleFromSchema builds a valid instance", () => {
  const v = sampleFromSchema({
    type: "object",
    properties: {
      reply: { type: "string" },
      done: { type: "boolean" },
      level: { type: "string", enum: ["A1", "A2"] },
      score: { type: "integer", minimum: 1, maximum: 5 },
      items: { type: "array", minItems: 2, items: { type: "object", properties: { w: { type: "string" } } } },
    },
  }) as Record<string, unknown>;
  assert.equal(typeof v.reply, "string");
  assert.equal(v.done, false);
  assert.equal(v.level, "A1");
  assert.equal(v.score, 3);
  assert.equal((v.items as unknown[]).length, 2);
});

test("mode markers win over the mode file", () => {
  assert.equal(pickMode("hello", undefined), "ok");
  assert.equal(pickMode("please #busy", undefined), "busy");
  assert.equal(pickMode("x", "Z:/no/such/file"), "ok");
});

test("stub client answers with schema JSON and throws SDK errors on markers", async () => {
  const c = stubClaude({}, async () => undefined);
  const schema = { type: "object", properties: { reply: { type: "string" } } };
  const ok = (await c.beta.messages.create({
    model: "m",
    max_tokens: 1,
    messages: [{ role: "user", content: "hi" }],
    output_config: { format: { type: "json_schema", schema } },
  } as never)) as unknown as { content: { text: string }[] };
  assert.equal(typeof JSON.parse(ok.content[0].text).reply, "string");

  const call = (text: string) =>
    c.beta.messages.create({ model: "m", max_tokens: 1, messages: [{ role: "user", content: text }] } as never);
  await assert.rejects(call("#busy"), (e) => e instanceof Anthropic.RateLimitError);
  await assert.rejects(call("#apierr"), (e) => e instanceof Anthropic.APIError);
  await assert.rejects(call("#crash"), (e) => !(e instanceof Anthropic.APIError));
  const refused = (await call("#refuse")) as unknown as { stop_reason: string };
  assert.equal(refused.stop_reason, "refusal");
});
