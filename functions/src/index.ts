import * as admin from "firebase-admin";
import { HttpsError, onCall, onRequest } from "firebase-functions/v2/https";

admin.initializeApp();

const db = admin.firestore();

/** Misma lista que en [UserRepository] (acceso admin sin doc en Firestore). */
const SEED_ADMIN_EMAILS = ["insumosacuarioml@gmail.com"];

async function applyAdminSetPassword(
  callerUid: string,
  callerEmail: string | undefined,
  targetUid: string,
  newPassword: string
): Promise<void> {
  if (!targetUid) {
    throw new HttpsError("invalid-argument", "Falta el usuario destino.");
  }
  if (newPassword.length < 6) {
    throw new HttpsError(
      "invalid-argument",
      "La contraseña debe tener al menos 6 caracteres."
    );
  }

  const callerDoc = await db.collection("users").doc(callerUid).get();
  const role = callerDoc.data()?.role;
  const email = (callerEmail || "").toLowerCase();
  const isAdmin = role === "admin" || SEED_ADMIN_EMAILS.includes(email);

  if (!isAdmin) {
    throw new HttpsError(
      "permission-denied",
      "Solo un administrador puede cambiar contraseñas."
    );
  }

  try {
    await admin.auth().updateUser(targetUid, { password: newPassword });
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    console.error("adminSetUserPassword updateUser", err);
    throw new HttpsError(
      "internal",
      msg || "No se pudo actualizar la contraseña en Authentication."
    );
  }
}

/** Callable (Android/iOS / SDK). */
export const adminSetUserPassword = onCall(
  { region: "us-central1" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Tenés que iniciar sesión.");
    }

    const raw = request.data as { targetUid?: unknown; newPassword?: unknown };
    const targetUid =
      typeof raw?.targetUid === "string" ? raw.targetUid.trim() : "";
    const newPassword =
      typeof raw?.newPassword === "string" ? raw.newPassword : "";

    await applyAdminSetPassword(
      request.auth.uid,
      request.auth.token.email,
      targetUid,
      newPassword
    );

    return { ok: true };
  }
);

function parseJsonBody(req: { body?: unknown }): Record<string, unknown> {
  const b = req.body;
  if (b && typeof b === "object" && !Array.isArray(b)) {
    return b as Record<string, unknown>;
  }
  if (typeof b === "string") {
    try {
      return JSON.parse(b) as Record<string, unknown>;
    } catch {
      return {};
    }
  }
  return {};
}

/** Cabeceras CORS manuales: `cors: true` del SDK no siempre permite `Authorization` en el preflight. */
function setCorsHeaders(res: {
  set: (name: string, value: string) => void;
}): void {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
  res.set(
    "Access-Control-Allow-Headers",
    "Content-Type, Authorization, X-Requested-With"
  );
  res.set("Access-Control-Max-Age", "86400");
}

/**
 * HTTP con CORS explícito para Flutter Web / localhost (fetch + Authorization).
 */
export const adminSetUserPasswordHttp = onRequest(
  {
    region: "us-central1",
    /** Gen2 = Cloud Run: sin esto el preflight OPTIONS recibe 403 sin CORS (parece fallo de CORS). */
    invoker: "public",
  },
  async (req, res) => {
    setCorsHeaders(res);

    if (req.method === "OPTIONS") {
      res.status(204).send("");
      return;
    }

    const sendErr = (status: number, code: string, message: string) => {
      setCorsHeaders(res);
      res.status(status).json({ error: { status: code, message } });
    };

    if (req.method !== "POST") {
      sendErr(405, "INVALID_ARGUMENT", "Usá POST.");
      return;
    }

    const authHeader = req.headers.authorization || "";
    const match = /^Bearer\s+(.+)$/i.exec(authHeader);
    if (!match) {
      sendErr(401, "UNAUTHENTICATED", "Token de autorización requerido.");
      return;
    }

    let decoded: admin.auth.DecodedIdToken;
    try {
      decoded = await admin.auth().verifyIdToken(match[1]);
    } catch {
      sendErr(401, "UNAUTHENTICATED", "Token inválido o vencido.");
      return;
    }

    const body = parseJsonBody(req);
    const targetUid =
      typeof body.targetUid === "string" ? body.targetUid.trim() : "";
    const newPassword =
      typeof body.newPassword === "string" ? body.newPassword : "";

    try {
      await applyAdminSetPassword(
        decoded.uid,
        decoded.email,
        targetUid,
        newPassword
      );
      setCorsHeaders(res);
      res.status(200).json({ ok: true });
    } catch (err: unknown) {
      if (err instanceof HttpsError) {
        const code = (err.code || "internal").toUpperCase().replace(/-/g, "_");
        const status =
          code === "PERMISSION_DENIED"
            ? 403
            : code === "UNAUTHENTICATED"
              ? 401
              : code === "INVALID_ARGUMENT"
                ? 400
                : 500;
        sendErr(status, code, err.message || "Error");
        return;
      }
      const msg = err instanceof Error ? err.message : String(err);
      sendErr(500, "INTERNAL", msg);
    }
  }
);
