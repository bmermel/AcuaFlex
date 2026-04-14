"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.adminSetUserPasswordHttp = exports.adminSetUserPassword = void 0;
const admin = __importStar(require("firebase-admin"));
const https_1 = require("firebase-functions/v2/https");
admin.initializeApp();
const db = admin.firestore();
/** Misma lista que en [UserRepository] (acceso admin sin doc en Firestore). */
const SEED_ADMIN_EMAILS = ["insumosacuarioml@gmail.com"];
async function applyAdminSetPassword(callerUid, callerEmail, targetUid, newPassword) {
    if (!targetUid) {
        throw new https_1.HttpsError("invalid-argument", "Falta el usuario destino.");
    }
    if (newPassword.length < 6) {
        throw new https_1.HttpsError("invalid-argument", "La contraseña debe tener al menos 6 caracteres.");
    }
    const callerDoc = await db.collection("users").doc(callerUid).get();
    const role = callerDoc.data()?.role;
    const email = (callerEmail || "").toLowerCase();
    const isAdmin = role === "admin" || SEED_ADMIN_EMAILS.includes(email);
    if (!isAdmin) {
        throw new https_1.HttpsError("permission-denied", "Solo un administrador puede cambiar contraseñas.");
    }
    try {
        await admin.auth().updateUser(targetUid, { password: newPassword });
    }
    catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        console.error("adminSetUserPassword updateUser", err);
        throw new https_1.HttpsError("internal", msg || "No se pudo actualizar la contraseña en Authentication.");
    }
}
/** Callable (Android/iOS / SDK). */
exports.adminSetUserPassword = (0, https_1.onCall)({ region: "us-central1" }, async (request) => {
    if (!request.auth) {
        throw new https_1.HttpsError("unauthenticated", "Tenés que iniciar sesión.");
    }
    const raw = request.data;
    const targetUid = typeof raw?.targetUid === "string" ? raw.targetUid.trim() : "";
    const newPassword = typeof raw?.newPassword === "string" ? raw.newPassword : "";
    await applyAdminSetPassword(request.auth.uid, request.auth.token.email, targetUid, newPassword);
    return { ok: true };
});
function parseJsonBody(req) {
    const b = req.body;
    if (b && typeof b === "object" && !Array.isArray(b)) {
        return b;
    }
    if (typeof b === "string") {
        try {
            return JSON.parse(b);
        }
        catch {
            return {};
        }
    }
    return {};
}
/** Cabeceras CORS manuales: `cors: true` del SDK no siempre permite `Authorization` en el preflight. */
function setCorsHeaders(res) {
    res.set("Access-Control-Allow-Origin", "*");
    res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
    res.set("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Requested-With");
    res.set("Access-Control-Max-Age", "86400");
}
/**
 * HTTP con CORS explícito para Flutter Web / localhost (fetch + Authorization).
 */
exports.adminSetUserPasswordHttp = (0, https_1.onRequest)({
    region: "us-central1",
    /** Gen2 = Cloud Run: sin esto el preflight OPTIONS recibe 403 sin CORS (parece fallo de CORS). */
    invoker: "public",
}, async (req, res) => {
    setCorsHeaders(res);
    if (req.method === "OPTIONS") {
        res.status(204).send("");
        return;
    }
    const sendErr = (status, code, message) => {
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
    let decoded;
    try {
        decoded = await admin.auth().verifyIdToken(match[1]);
    }
    catch {
        sendErr(401, "UNAUTHENTICATED", "Token inválido o vencido.");
        return;
    }
    const body = parseJsonBody(req);
    const targetUid = typeof body.targetUid === "string" ? body.targetUid.trim() : "";
    const newPassword = typeof body.newPassword === "string" ? body.newPassword : "";
    try {
        await applyAdminSetPassword(decoded.uid, decoded.email, targetUid, newPassword);
        setCorsHeaders(res);
        res.status(200).json({ ok: true });
    }
    catch (err) {
        if (err instanceof https_1.HttpsError) {
            const code = (err.code || "internal").toUpperCase().replace(/-/g, "_");
            const status = code === "PERMISSION_DENIED"
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
});
//# sourceMappingURL=index.js.map