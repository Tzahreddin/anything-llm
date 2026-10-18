"use strict";

const fs = require("node:fs");
const http = require("node:http");
const path = require("node:path");
const { resolveBridgeIdentity } = require("./lib/identity.js");
const { createAllmClient } = require("./lib/allmClient.js");

const MSG_DENY_UNMAPPED =
  "Zugriff verweigert. Ihr Konto ist nicht für AnythingLLM freigeschaltet.";
const MSG_DENY_NOT_PROVISIONED =
  "Zugriff verweigert. Der AnythingLLM-Benutzer ist nicht freigeschaltet.";
const MSG_BAD_GATEWAY =
  "AnythingLLM ist vorübergehend nicht erreichbar. Bitte später erneut versuchen.";

function autoCreateEnabled(value) {
  return String(value ?? "") === "1";
}

function loadIdentityMap(mapPath) {
  const resolved = path.resolve(mapPath);
  const raw = fs.readFileSync(resolved, "utf8");
  return JSON.parse(raw);
}

function defaultMapPath() {
  return (
    process.env.ALLM_SSO_BRIDGE_MAP_PATH ||
    path.join(__dirname, "identity-map.json")
  );
}

function joinPublicRedirect(publicBase, loginPath, redirectTo) {
  const base = String(publicBase || "").replace(/\/+$/, "");
  let suffix = String(loginPath || "");
  if (!suffix.startsWith("/")) {
    suffix = `/${suffix}`;
  }
  let location = `${base}${suffix}`;
  if (redirectTo) {
    location += `${location.includes("?") ? "&" : "?"}redirectTo=${encodeURIComponent(
      redirectTo
    )}`;
  }
  return location;
}

function sendText(res, statusCode, body) {
  const payload = Buffer.from(body, "utf8");
  res.writeHead(statusCode, {
    "Content-Type": "text/plain; charset=utf-8",
    "Content-Length": String(payload.length),
    "Cache-Control": "no-store",
  });
  res.end(payload);
}

function requestPath(req) {
  try {
    return new URL(req.url || "/", "http://bridge.local").pathname;
  } catch {
    return "/";
  }
}

const silentLog = {
  info() {},
  error() {},
};

function jsonLogger() {
  return {
    info(obj) {
      console.info(JSON.stringify(obj));
    },
    error(obj) {
      console.error(JSON.stringify(obj));
    },
  };
}

function createRequestHandler(options = {}) {
  const identityMap = options.identityMap ?? {};
  const publicBase = options.publicBase ?? "";
  const redirectTo = options.redirectTo;
  const autoCreate = Boolean(options.autoCreate);
  const log = options.log ?? silentLog;
  const allmClient =
    options.allmClient ??
    createAllmClient({
      baseUrl: options.allmBaseUrl,
      apiKey: options.apiKey,
      fetchImpl: options.fetchImpl,
    });

  return async function handleRequest(req, res) {
    const method = req.method || "GET";
    const pathname = requestPath(req);

    if (method === "GET" && pathname === "/health") {
      sendText(res, 200, "ok");
      return;
    }

    const ssoStart = pathname === "/sso/start" || pathname === "/";
    if (method === "GET" && ssoStart) {
      const identity = resolveBridgeIdentity(req.headers, identityMap);
      if (identity.status !== "ok") {
        log.info?.({
          msg: "sso-deny",
          authentikIdentity: identity.authentikIdentity,
        });
        sendText(res, 403, MSG_DENY_UNMAPPED);
        return;
      }

      let issued;
      try {
        issued = await allmClient.issueSimpleSsoLogin({
          allmUsername: identity.allmUsername,
          autoCreate,
        });
      } catch {
        log.error?.({
          msg: "sso-allm-exception",
          authentikIdentity: identity.authentikIdentity,
          allmUsername: identity.allmUsername,
        });
        sendText(res, 502, MSG_BAD_GATEWAY);
        return;
      }

      if (issued.status === "missing") {
        log.info?.({
          msg: "sso-allm-user-missing",
          authentikIdentity: identity.authentikIdentity,
          allmUsername: identity.allmUsername,
        });
        sendText(res, 403, MSG_DENY_NOT_PROVISIONED);
        return;
      }

      if (issued.status !== "ok" || !issued.loginPath) {
        log.error?.({
          msg: "sso-allm-failure",
          authentikIdentity: identity.authentikIdentity,
          allmUsername: identity.allmUsername,
          reason: issued.reason,
        });
        sendText(res, 502, MSG_BAD_GATEWAY);
        return;
      }

      const location = joinPublicRedirect(
        publicBase,
        issued.loginPath,
        redirectTo
      );
      log.info?.({
        msg: "sso-redirect",
        authentikIdentity: identity.authentikIdentity,
        allmUsername: identity.allmUsername,
      });
      res.writeHead(302, {
        Location: location,
        "Cache-Control": "no-store",
      });
      res.end();
      return;
    }

    sendText(res, 404, "Not found");
  };
}

function loadRuntimeOptions(env = process.env) {
  return {
    identityMap: loadIdentityMap(env.ALLM_SSO_BRIDGE_MAP_PATH || defaultMapPath()),
    allmBaseUrl: env.ALLM_SSO_BRIDGE_ALLM_BASE_URL,
    apiKey: env.ANYTHINGLLM_API_KEY,
    publicBase: env.ALLM_SSO_BRIDGE_PUBLIC_BASE,
    autoCreate: autoCreateEnabled(env.ALLM_SSO_BRIDGE_AUTO_CREATE),
    redirectTo: env.ALLM_SSO_BRIDGE_REDIRECT_TO || undefined,
    port: Number(env.ALLM_SSO_BRIDGE_PORT || env.PORT || 8080),
    host: env.ALLM_SSO_BRIDGE_HOST || "0.0.0.0",
  };
}

function startServer(options = {}) {
  const runtime = {
    ...loadRuntimeOptions(options.env || process.env),
    ...options,
  };
  if (!runtime.log) {
    runtime.log = jsonLogger();
  }
  const handler = createRequestHandler(runtime);
  const server = http.createServer((req, res) => {
    Promise.resolve(handler(req, res)).catch(() => {
      if (!res.headersSent) {
        sendText(res, 502, MSG_BAD_GATEWAY);
      }
    });
  });
  return new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(runtime.port, runtime.host, () => {
      console.info(
        JSON.stringify({
          msg: "listening",
          host: runtime.host,
          port: runtime.port,
        })
      );
      resolve(server);
    });
  });
}

if (require.main === module) {
  startServer().catch((err) => {
    console.error(JSON.stringify({ msg: "startup-failed" }));
    process.exitCode = 1;
    if (err && process.env.ALLM_SSO_BRIDGE_DEBUG === "1") {
      console.error(err.message);
    }
  });
}

module.exports = {
  MSG_DENY_UNMAPPED,
  MSG_DENY_NOT_PROVISIONED,
  MSG_BAD_GATEWAY,
  autoCreateEnabled,
  jsonLogger,
  createRequestHandler,
  joinPublicRedirect,
  loadIdentityMap,
  loadRuntimeOptions,
  startServer,
};
