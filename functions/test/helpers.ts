import { getApps, initializeApp } from "firebase-admin/app";
import { Firestore, getFirestore } from "firebase-admin/firestore";

export const PROJECT_ID = "demo-lingora";

export function emulatorHost(): string {
  const host = process.env.FIRESTORE_EMULATOR_HOST;
  if (!host) throw new Error("Run through `npm test` (needs the Firestore emulator).");
  return host;
}

export function adminDb(): Firestore {
  emulatorHost();
  const app = getApps()[0] ?? initializeApp({ projectId: PROJECT_ID });
  return getFirestore(app);
}

export async function clearFirestore(): Promise<void> {
  const res = await fetch(
    `http://${emulatorHost()}/emulator/v1/projects/${PROJECT_ID}/databases/(default)/documents`,
    { method: "DELETE" },
  );
  if (!res.ok) throw new Error(`clear failed: ${res.status}`);
}

/** Asserts that [p] rejects with an HttpsError of [code]. */
export async function rejectsWith(p: Promise<unknown>, code: string, message?: string): Promise<void> {
  try {
    await p;
  } catch (e) {
    const err = e as { code?: string; message?: string };
    if (err.code !== code) throw new Error(`expected ${code}, got ${err.code}: ${err.message}`);
    if (message && err.message !== message) throw new Error(`expected "${message}", got "${err.message}"`);
    return;
  }
  throw new Error(`expected rejection with ${code}`);
}
