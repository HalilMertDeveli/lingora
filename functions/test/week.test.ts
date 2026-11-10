import assert from "node:assert/strict";
import { test } from "node:test";

import { dayKey, previousWeekKey, weekKey } from "../src/week.js";

test("week starts Monday 00:00 Turkish time", () => {
  // Sunday 20:59 UTC = Sunday 23:59 in Türkiye -> still the old week.
  assert.equal(weekKey(new Date("2026-11-15T20:59:00Z")), "2026-11-09");
  // Sunday 21:00 UTC = Monday 00:00 in Türkiye -> new week.
  assert.equal(weekKey(new Date("2026-11-15T21:00:00Z")), "2026-11-16");
  assert.equal(weekKey(new Date("2026-11-10T12:00:00Z")), "2026-11-09");
  assert.equal(previousWeekKey(new Date("2026-11-10T12:00:00Z")), "2026-11-02");
  assert.equal(dayKey(new Date("2026-12-31T22:30:00Z")), "2027-01-01");
});
