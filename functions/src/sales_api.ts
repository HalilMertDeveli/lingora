// HTTP and callable wrappers for Dilmaç Kurumsal sales (logic: sales.ts).
import { Firestore, getFirestore } from "firebase-admin/firestore";
import { CallableRequest, HttpsError, onCall, onRequest } from "firebase-functions/v2/https";

import type { Caller } from "./orgs.js";
import * as sales from "./sales.js";

/**
 * POST /api/kurumsal-talep (Firebase Hosting rewrite, so same origin as the
 * /kurumsal page): the quote request form. JSON in, {ok, error?, fields?} out.
 */
export const submitLead = onRequest(
  { region: "europe-west1", maxInstances: 2, concurrency: 20, memory: "256MiB", invoker: "public" },
  async (req, res) => {
    res.set("Cache-Control", "no-store");
    res.set("X-Content-Type-Options", "nosniff");
    // Firebase Hosting puts the visitor's address in Fastly-Client-IP.
    const ip = String(req.get("fastly-client-ip") ?? req.ip ?? "");
    const out = await sales.handleLeadRequest(
      getFirestore(),
      { method: req.method, origin: req.get("origin") ?? undefined, ip, body: req.body },
      new Date(),
    );
    res.status(out.status).json(out.body);
  },
);

type Handler<T> = (db: Firestore, caller: Caller, data: unknown, now: Date) => Promise<T>;

function staffCallable<T>(handler: Handler<T>) {
  return onCall({ region: "europe-west1", maxInstances: 5 }, (req: CallableRequest) => {
    if (!req.auth) throw new HttpsError("unauthenticated", "sign_in_required");
    return handler(getFirestore(), { uid: req.auth.uid, claims: req.auth.token }, req.data, new Date());
  });
}

// Admin panel (lib/admin), Dilmaç staff only: "Talepler" and "Deneme kodu".
export const leadList = staffCallable(sales.listLeads);
export const leadUpdate = staffCallable(sales.updateLead);
export const leadDelete = staffCallable(sales.deleteLead);
export const trialCreate = staffCallable(sales.createTrial);
