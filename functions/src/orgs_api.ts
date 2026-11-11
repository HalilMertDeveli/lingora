// Callable wrappers for Dilbaz Kurumsal (logic and data model: orgs.ts).
import { Firestore, getFirestore } from "firebase-admin/firestore";
import { CallableRequest, HttpsError, onCall } from "firebase-functions/v2/https";

import * as orgs from "./orgs.js";

type Handler<T> = (db: Firestore, caller: orgs.Caller, data: unknown, now: Date) => Promise<T>;

function callable<T>(handler: Handler<T>) {
  // Region spelled out so these do not depend on setGlobalOptions() order.
  return onCall({ region: "europe-west1", maxInstances: 10 }, (req: CallableRequest) => {
    if (!req.auth) throw new HttpsError("unauthenticated", "sign_in_required");
    return handler(getFirestore(), { uid: req.auth.uid, claims: req.auth.token }, req.data, new Date());
  });
}

// Dilbaz staff (custom claim isLingoraAdmin or config/lingoraAdmins).
export const orgCreate = callable(orgs.createOrg);
export const orgUpdate = callable(orgs.updateOrg);
// Panel.
export const orgList = callable(orgs.listOrgs);
export const orgReport = callable(orgs.orgReport);
export const orgCreateCode = callable(orgs.createJoinCode);
export const orgRevokeCode = callable(orgs.revokeJoinCode);
export const orgRotateCode = callable(orgs.rotateJoinCode);
export const orgRemoveMember = callable(orgs.removeMember);
export const orgSetRole = callable(orgs.setMemberRole);
export const orgCreateClass = callable(orgs.createClass);
export const orgDeleteClass = callable(orgs.deleteClass);
export const orgSetClassMember = callable(orgs.setClassMember);
export const orgCreateAssignment = callable(orgs.createAssignment);
export const orgDeleteAssignment = callable(orgs.deleteAssignment);
// App.
export const orgJoin = callable(orgs.joinOrg);
export const orgLeave = callable(orgs.leaveOrg);
export const orgMine = callable(orgs.getMyOrg);
