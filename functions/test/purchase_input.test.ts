import assert from "node:assert/strict";
import { test } from "node:test";

import { PACK_PRODUCTS, PRODUCTS, parsePurchaseInput } from "../src/purchase.js";

test("only configured products pass purchase validation", () => {
  for (const productId of [...Object.keys(PRODUCTS), ...Object.keys(PACK_PRODUCTS)]) {
    assert.deepEqual(parsePurchaseInput({ productId, purchaseToken: "valid-token-123" }), {
      productId, purchaseToken: "valid-token-123",
    });
  }
  for (const productId of ["toString", "constructor", "__proto__", "hasOwnProperty", "unknown"]) {
    assert.throws(() => parsePurchaseInput({ productId, purchaseToken: "valid-token-123" }), {
      code: "invalid-argument", message: "unknown_product",
    });
  }
});
